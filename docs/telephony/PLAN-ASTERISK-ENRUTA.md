# Plan «Asterisk enruta, Chatwoot atiende» — traspaso a la sesión en la nube

Plan aprobado por el usuario el 2026-09-25 (página: https://claude.ai/artifact/Ds51oHg1b1KxDfiJorriXS).
Instrucción del usuario: **implementar todas las fases en código primero; todo lo que requiera la VM de
la PBX o producción (fase 0 y pruebas reales) se hace al final, con él.**

## Modelo

FreePBX hace TODO el enrutamiento: DID → IVR / agente de voz «gestor de enrutamiento» → cola / ring group
→ extensiones; horarios, música, rutas de salida, permisos y caller ID por extensión. Chatwoot:

- configura la troncal del carrier (creada como **troncal nativa de FreePBX**, visible en Connectivity →
  Trunks y usable en Outbound Routes) y la extensión de cada agente;
- mapea número → canal: DIDs del carrier → inbox de Telefonía; número de WhatsApp → su inbox de WhatsApp;
- es el teléfono del agente (softphone en el navegador) y **observa** las llamadas que FreePBX hace sonar en
  las extensiones de los agentes: tarjeta, conversación, historial y grabación, **sin decidir a quién suena**.

## Decisiones tomadas

| | Decisión |
|---|---|
| D1 | Troncal nativa: se configura en Chatwoot y pbx-provisioner la crea en la base de FreePBX (tablas `trunks` + `pjsip`, `fwconsole reload`). Si en la fase 0 no resulta fiable → caer a «la creas en la GUI y Chatwoot la referencia». |
| D2 | Detección por ARI: el controlador suscribe su app a `endpoint:PJSIP/<ext>` de cada extensión vinculada (`POST /ari/applications/<app>/subscription?eventSource=...`), sin Stasis. DID y correlación por `channelvars = FROM_DID,CHANNEL(linkedid)` en `ari.conf` (validar en fase 0). Alternativa si falla: AMI. |
| D3 | Grabación de llamadas enrutadas por FreePBX: la hace FreePBX (cola/extensión, *Call Recording*); el provisioner sirve el archivo por linkedid y Chatwoot lo adjunta con el `RecordingFetchJob` existente. OJO: hay fallos conocidos de CDR/CEL ODBC en FreePBX; la fase 0 debe confirmar que el CDR escribe `linkedid`/`recordingfile`, o localizar el archivo por nombre en `/var/spool/asterisk/monitor`. |
| D4 | Salientes: se mantiene el clic para llamar (ARI origina la pata del agente y `Local/<num>@from-internal`), con el caller ID de la **extensión del agente** para que apliquen permisos/CID/rutas de FreePBX. |
| D5 | Las reglas de enrutamiento de Chatwoot (agente asignado, equipo, bot de voz, expansión de ring groups, hint) quedan como **destino opcional «Chatwoot»** de FreePBX (Custom Destination `chatwoot-inbound,s,1`, que ya existe). No se borran. |

## Fases a implementar (código)

**Fase 1 — Troncal nativa y DIDs como mapa de canales** (fork + controlador + `ISP-K8s-Platform/vm/pbx`)
- pbx-provisioner: crear/actualizar/borrar la troncal de cada cuenta como troncal de FreePBX (nombre sugerido
  `chatwoot-<account>`) escribiendo `trunks` y `pjsip` como lo hace el módulo Core de FreePBX 17, y
  `fwconsole reload`. El esquema exacto se confirma en la fase 0 (el usuario pegará `select * from trunks`
  y `select keyword,data,flags from pjsip where id=<trunkid>` de una troncal creada en la GUI); dejar el
  mapeo de claves aislado en una función con tests para ajustarlo fácil.
- Dejar de escribir la troncal del carrier en `pjsip.*_custom.conf` (el modo «Configurar aquí» actual) y de
  crear Inbound Routes para los DIDs del carrier (el admin elige el destino en FreePBX). Las troncales `wa-*`
  siguen en `pjsip_custom` (FreePBX no admite su TLS/DTLS) y su Inbound Route se crea solo si no existe.
- Firewall `chatwoot_carriers` (IPs del carrier desde Chatwoot): se queda igual.
- Salida siempre por `Local/<num>@from-internal` (Outbound Routes). Modos de troncal: «Chatwoot la crea en
  FreePBX» / «Ya existe en FreePBX». Migrar los existentes (`custom`→nativa, `gui`/`routes`→existente).
- **Retirar** de la tanda T2 sin desplegar: `dial_format`, `dial_prefix`, `allowed_prefixes` (lo hacen los
  patrones de Outbound Routes) — columnas, validaciones, UI, i18n en/es, controlador y tests.
- DIDs: siguen siendo únicos entre cuentas; además deciden el inbox de la conversación.

**Fase 2 — Observador de llamadas en el controlador** (lo central)
- Al vincular/desvincular una extensión (y al arrancar/reconectar ARI) suscribir/desuscribir `endpoint:PJSIP/<ext>`.
- Llamada observada (`calls.source = 'pbx'`, sin Stasis): nace cuando suena la primera extensión de un agente;
  agrupa patas por linkedid; `ringing_user_ids` = agentes cuya extensión suena (una cola timbra a varios),
  `answered_by`/`user_id` = quien contesta (ChannelStateChange Up en su canal), fin con `ChannelDestroyed`
  de todas las patas. Transferencias (REFER o de FreePBX): la llamada pasa al nuevo agente.
- Avisar a Rails como hoy (outbox → `internal_events`) y un callback de alta equivalente a `internal_inbound`
  sin plan: Rails resuelve el inbox por el DID (carrier → Telefonía; número WhatsApp → inbox WhatsApp), el
  contacto por el número que llama, la conversación, y crea la `CallProjection`. Reutilizar tarjeta,
  `NoteProjector`, historial (M05), `ringing_user_ids` como en ring groups expandidos.
- Llamadas que no tocan ninguna extensión de agente (IVR → buzón, abandono en cola): opcional, registrarlas
  como perdidas leyendo CDR; dejarlo detrás de un flag si se hace.

**Fase 3 — Softphone con control SIP** (fork, `useSipSession.js`, store `telephony.js`, `CallWidget.vue`)
- Tarjeta para cualquier INVITE a la extensión del agente (hoy `onInvite` lo acepta pero no hay tarjeta si el
  controlador no lo anunció): correlacionar con la llamada observada (evento del controlador) y, en su defecto,
  mostrar tarjeta mínima con el número que llama.
- En llamadas observadas: espera por re-INVITE (FreePBX pone su música), transferencia ciega por REFER a
  extensión / cola / ring group (lista desde FreePBX), DTMF RFC 4733, colgar local. Las del clic para llamar
  siguen por el API del controlador.

**Fase 4 — Grabación de FreePBX**: endpoint del provisioner para servir la grabación por linkedid (con
acotado de rutas como el resto), el controlador la anuncia al terminar la llamada observada y el job de
recogida existente la adjunta; el barrido de grabaciones perdidas funciona igual.

**Fase 5 — Salientes, destino «Chatwoot» y docs**: caller ID de la extensión en el clic para llamar; UI de la
pestaña Telefonía explicando el destino opcional «Chatwoot»; actualizar `ISP-K8s-Platform/docs/telephony/
TRONCAL-SIP.md` y `RUNBOOK-telephony.md` con el modelo nuevo y ejemplos (IVR → cola, agente de voz → cola,
horario → buzón).

## Fase 0 (al final, con el usuario, en la VM)

Observador listo en `telephony-controller/scripts/spike/observe-ari.cjs` (app ARI `cw-spike`, no toca la
app `chatwoot`; se ejecuta en el pod del controlador). Pasos que el usuario debe hacer en la VM/GUI:
`channelvars = FROM_DID,CHANNEL(linkedid)` en `/etc/asterisk/ari_general_custom.conf` + `module reload
res_ari.so` (luego llevarlo a la plantilla del overlay); colas de prueba 700 (1001,1002, ringall, recording
force) y 701 (`*43`), Inbound Routes DID `999000700`/`999000701`; troncal de prueba `spike-trunk` en la GUI
para volcar `trunks`/`pjsip`; comprobar módulos (`core`, `queues`, `callrecording`, `cdr`), `cdr show status`
y `allow_transfer` de 1001. Luego: simular entrantes con el observador y validar hold/REFER desde el navegador.

## Estado de los repositorios al traspaso

- Fork Chatwoot `codex/isp-image`: T1+T2+T3 de la auditoría de la troncal (commits `ff3c352453`,
  `6df113f4d0`); etiqueta `v4.17.1-isp.10` = T1 + merge de develop + dataset exports (CI completo verde).
  Producción sigue en `isp.9`. T2 sin etiquetar (M2/M3 se retiran en la fase 1).
- telephony-controller `main`: T1 `690bbba` (= `v0.1.11`), T2 `8df3d89`, observador `c5e1d16`. Producción en `v0.1.10`.
- ISP-K8s-Platform `master`: T1 `8f17acc`, T2/T3 `51b76f3`. Nada desplegado en la VM.
- Informe de la auditoría: https://claude.ai/artifact/DAPHu1K3VyNUPPP27bhuyc

## Reglas del proyecto (obligatorias)

- **Nunca** vaciar/recrear/borrar bases de datos (hay un hook que lo bloquea; tampoco escribir texto
  «DELETE FROM x» sin WHERE en tests: pendiente la decisión del usuario sobre `test/server-trunk.test.ts`).
- Despliegues, etiquetas y cambios en producción/VM **solo con autorización explícita** del usuario, uno por uno.
  Commits y push a las ramas de trabajo sí.
- i18n: cada string nuevo en `en` **y** `es` (json y yml). Commits del fork sin mencionar a Claude;
  en controlador e infra con `Co-Authored-By`.
- Specs: Rails (`bundle exec rspec`), controlador (`npx vitest run`, `npx tsc --noEmit`, `npm run lint`),
  provisioner (`python3 -m unittest` en `vm/pbx/provisioner`).
