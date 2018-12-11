# name:ldap
# about: A plugin to provide ldap authentication.
# version: 0.3.8
# authors: Jon Bake <jonmbake@gmail.com>

enabled_site_setting :ldap2_enabled

gem 'pyu-ruby-sasl', '0.0.3.3', require: false
gem 'rubyntlm', '0.3.4', require: false
gem 'net-ldap', '0.14.0'
gem 'omniauth-ldap', '1.0.5'

require 'yaml'
require_relative 'lib/ldap_user'

class LDAPAuthenticator2 < ::Auth::Authenticator
  def name
    'ldap'
  end

  def enabled?
    true
  end

  def after_authenticate(auth_options)
    return auth_result(auth_options.info)
  end

  def register_middleware(omniauth)
    omniauth.configure{ |c| c.form_css = File.read(File.expand_path("../css/form.css", __FILE__)) }
    omniauth.provider :ldap,
      setup:  -> (env) {
        env["omniauth.strategy"].options.merge!(
          host: SiteSetting.ldap2_hostname,
          port: SiteSetting.ldap2_port,
          method: SiteSetting.ldap2_method,
          base: SiteSetting.ldap2_base,
          uid: SiteSetting.ldap2_uid,
          # In 0.3.0, we fixed a typo in the ldap_bind_dn config name. This fallback will be removed in a future version.
          bind_dn: SiteSetting.ldap_bind_dn.presence || SiteSetting.try(:ldap2_bind_db),
          password: SiteSetting.ldap2_password,
          filter: SiteSetting.ldap2_filter
        )
      }
  end

  private
  def auth_result(auth_info)
    case SiteSetting.ldap2_user_create_mode
      when 'none'
        ldap_user = LDAPUser2.new(auth_info)
        return ldap_user.account_exists? ? ldap_user.auth_result : fail_auth('User account does not exist.')
      when 'list'
        user_descriptions = load_user_descriptions
        return fail_auth('List of users must be provided when ldap2_user_create_mode setting is set to \'list\'.') if user_descriptions.nil?
        #match on email
        match = user_descriptions.find { |ud|  auth_info[:email].casecmp(ud[:email]) == 0 }
        return fail_auth('User with email is not listed in LDAP user list.') if match.nil?
        match[:nickname] = match[:username] || auth_info[:nickname]
        match[:name] = match[:name] || auth_info[:name]
        return LDAPUser2.new(match).auth_result
      when 'auto'
        return LDAPUser2.new(auth_info).auth_result
      else
        return fail_auth('Invalid option for ldap2_user_create_mode setting.')
    end
  end
  def fail_auth(reason)
    result = Auth::Result.new
    result.failed = true
    result.failed_reason = reason
    result
  end
  def load_user_descriptions
    file_path = "#{File.expand_path(File.dirname(__FILE__))}/ldap_users.yml"
    return nil unless File.exists?(file_path)
    return YAML.load_file(file_path)
  end
end

auth_provider title: 'with CSU.LOCAL',
  message: 'Log in with your CSU.LOCAL credentials',
  frame_width: 920,
  frame_height: 800,
  authenticator: LDAPAuthenticator2.new

register_css <<CSS
  .btn {
    &.ldap {
      background-color: #517693;
      &:before {
        content: $fa-var-sitemap;
      }
    }
  }
CSS