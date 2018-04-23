# -*- encoding : utf-8 -*-
module PolicyManager::Concerns::UserBehavior
  extend ActiveSupport::Concern

  included do
    has_many :user_terms, class_name: "PolicyManager::UserTerm", autosave: true
    has_many :terms, through: :user_terms
    has_many :portability_requests, class_name: "PolicyManager::PortabilityRequest"

    # adds policies
    PolicyManager::Config.rules.each do |rule|
      # next if rule. !internal?
      rule_name = "policy_rule_#{rule.name}".to_sym
      
      attr_accessor rule_name

      if rule.validates_on

        validate :"check_#{rule_name}", :on => rule.validates_on, :if => ->(o){ 
          return true if rule.if.nil? 
          rule.if.call(o) rescue true 
        }

        define_method :"check_#{rule_name}" do
          if self.send(rule_name).blank? && needs_policy_confirmation_for?(rule.name)
            errors.add(rule_name, "needs confirmation")
          end
        end  
      end  
      
      define_method :"has_consented_#{rule.name}?" do
        !needs_policy_confirmation_for?(rule.name)
      end

      define_method :"#{rule_name}=" do |val=true|
        self.instance_variable_set("@#{rule_name}", val)
        ut = user_terms.new
        ut.term = policy_term_on(rule.name)
        val ? ut.accept : ut.reject
      end
    end

    # adds portability rules
    PolicyManager::Config.portability_rules.each do |rule|

      if rule.collection 
        define_method :"portability_collection_#{rule.name}" do |page=1|
          portability_collection_for(rule, page)
        end
      end

      if rule.member
        define_method :"portability_member_#{rule.name}" do
          portability_member_for(rule)
        end
      end
    end
  end

  def 

  def portability_schema
    PolicyManager::Config.portability_rules.map(&:name)
  end

  def portability_member_for(rule)
    self.send(rule.member)
  end

  def portability_collection_for(rule, page)
    # if kaminari
    # self.send(rule.collection).page(1)
    # if will paginate
    self.send(rule.collection).paginate(page: page, per_page: rule.per)
  end

  def pending_policies
    # TODO: this seems to be a litle inefficient, 
    # hint: try to do this in one query
    PolicyManager::Config.rules.select do |c|
      self.needs_policy_confirmation_for?(c.name)
    end
  end

  def pending_blocking_policies
    PolicyManager::Config.rules.select do |c|
      c.blocking && self.needs_policy_confirmation_for?(c.name)
    end
  end

  def confirm_all_policies!
    peding_policies.each do |c|
      term = c.terms.last
      current_user.handle_policy_for(term).accept!
    end
  end

  def reject_all_policies!
    peding_policies.each do |c|
      term = c.terms.last
      current_user.handle_policy_for(term).reject!
    end
  end

  def needs_policy_confirmation_for?(rule)
    term = policy_term_on(rule)
    user_term = policy_user_term_on(term)
    return true if user_term.blank?
    return true if user_term.rejected?
    term.created_at > user_term.created_at
  end

  def policy_term_on(rule)
    category = PolicyManager::Config.rules.find{|o| o.name == rule}
    term = category.terms.last
    raise "no term for #{rule} policy" if term.blank?
    term
  end

  def policy_user_term_on(term)
    return if term.blank?
    self.user_terms.where(term_id: term.id).first
  end

  def handle_policy_for(term)
    self.user_terms.where(term_id: term).first_or_initialize do |member|
      member.term_id = term.id
    end
  end

  def can_request_portability?
    self.portability_requests.select{|p| p.pending? || p.progress?}.blank?
  end

end