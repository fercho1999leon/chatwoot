# Reglas de enrutamiento de entrantes (administradores). Orden = posición.
class Api::V1::Accounts::Telephony::RoutingRulesController < Api::V1::Accounts::Telephony::BaseController
  before_action :check_authorization
  before_action :fetch_rule, only: [:update, :destroy]

  def index
    render json: Current.account.telephony_routing_rules.ordered
  end

  def create
    rule = Current.account.telephony_routing_rules.new(rule_params)
    rule.position = (Current.account.telephony_routing_rules.maximum(:position) || -1) + 1
    rule.save!
    render json: rule
  end

  def update
    @rule.update!(rule_params)
    render json: @rule
  end

  def destroy
    @rule.destroy!
    head :no_content
  end

  # POST reorder { ids: [3, 1, 2] }
  def reorder
    ids = Array(params[:ids]).map(&:to_i)
    Current.account.telephony_routing_rules.where(id: ids).find_each do |rule|
      rule.update!(position: ids.index(rule.id))
    end
    render json: Current.account.telephony_routing_rules.ordered
  end

  private

  def fetch_rule
    @rule = Current.account.telephony_routing_rules.find(params[:id])
  end

  def rule_params
    params.require(:routing_rule).permit(:name, :enabled, conditions: Telephony::RoutingRule::CONDITION_KEYS,
                                                          destination: Telephony::RoutingRule::DESTINATION_KEYS)
  end

  def check_authorization
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end
end
