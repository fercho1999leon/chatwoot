import { frontendURL } from '../../../../helper/URLHelper';

import SettingsWrapper from '../SettingsWrapper.vue';
import DatasetExportsHome from './Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/dataset-exports'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          redirect: to => {
            return { name: 'dataset_exports_list', params: to.params };
          },
        },
        {
          path: 'list',
          name: 'dataset_exports_list',
          meta: {
            permissions: ['administrator'],
          },
          component: DatasetExportsHome,
        },
      ],
    },
  ],
};
