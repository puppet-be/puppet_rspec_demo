require 'puppet'
require 'puppet/property/boolean'
require 'puppet/property/ordered_list'
require 'pry'

Puppet::Type.newtype(:ldapconfig) do

  @doc = "The config backend manages all of the configuration information
    for the slapd(8) daemon. This configuration information is also used
    by the SLAPD tools slapacl(8), slapadd(8), slapauth(8), slapcat(8),
    slapdn(8), slapindex(8), and slaptest(8).

    The config backend is backward compatible with the older slapd.conf(5)
    file but provides the ability to change the configuration dynamically
    at runtime. If slapd is run with only a slapd.conf file dynamic changes
    will be allowed but they will not persist across a server restart. Dynamic
    changes are only saved when slapd is running from a slapd.d configuration
    directory.

    Unlike other backends, there can only be one instance of the config backend,
    and most of its structure is predefined. The root of the database is hardcoded
    to cn=config and this root entry contains global settings for slapd"

  # we will group the properies like we did in the rspec file
  # for tag v.0.0.1, thishas no imapct, but we will keep the code
  # grouped when doing specific adjustments

  newproperty(:ensure, :parent => Puppet::Property::Ensure) do
    desc "The basic state that the object shoul be in"

    # if the ensure property is 'present', then this will trigger
    # the event :config_created.  The logic is written inn  the provider code
    # because implentation will differ from distro/OS/Platform
    newvalue(:present, :event => :config_created) do
      provider.create
    end
    newvalue(:absent, :event => :config_removed) do
      provider.delete
    end

    # here we define the default value depending if the reaource is managed or not.

    defaultto do
      if @resource.managed?
        :present
      else
        nil
      end
    end

    def retrieve
      if provider.exists?
        :present
      else
        :absent
      end
    end

  end

  #
  # string_properties
  #

  newproperty(:attributeoptions) do
    desc "Define tagging attribute options or option tag/range prefixes. Options must not end with \'-\', prefixes must end with \'-\'"
  end

  # we need to allow multiple values to be set, array_matching defaults to first
  newproperty(:saslsecprops, :array_matching => :all) do
    desc "The SASL secprops to apply. Defaults to \'noanonymous,noplain\'."
    defaultto ['noanonymous', 'noplain']
    # we cannot use newvalues, because we have specific validations depending on the values used
    # order should not be  important
    validate do | value |
      # we fail on the first fail
      case value
      when 'none', 'noanonymous', 'noplain', 'noactive', 'nodict', 'forwardsec', 'passcred'
        # passed
      when /^minssf=/,/^maxssf=/
        case value.split('=',2)[1]
        when "0", "1", "56", "112", "128"
          # passed
        else
          raise ArgumentError, "property saslsecprops : #{value}= should have a value of [0|1|56|112|128]"
        end
      when /^maxbufsize=/
        # The Integer() function raises an error if it has a 'non' decimal string
        totest = Integer(value.split('=',2)[1])
        if totest >= 0 || totest <= 65536
          # passed
        else
          raise ArgumentError, "property saslsecprops : #{value}= must be between 0 and 65536. See man slapd-config"
        end
      else
        raise ArgumentError, "property saslsecprops : #{value} not allowed. See man slapd-config"
      end
    end
  end

  newproperty(:tlsverifyclient) do
    # here we can use the newvalues for validation.
    # for single values params, be ware that by default Symbols are used
    # so everything is converted
    desc "Specifies what checks to perform on client certificates in an incoming TLS session, if any"
    defaultto 'never'
    newvalues('never','allow','try','demand','hard','true')
  end

  newproperty(:loglevel, :array_matching => :all) do
    desc " Specify the level at which debugging statements and operation statistics should be syslogged (currently logged to the syslogd(8) LOG_LOCAL4 facility)."
    # we default to 'none', so we force it here.  (openldap defaults to 0) - setting logging of has to be done using the 0 value
    defaultto :none
    # in ldap config, BER/ACL are uppercase, but since we will use the -or- ed value, we use case insensitive labels
    loglevels = [:off, :trace, :packets, :args, :conns, :ber, :filter, :config, :acl, :stats, :stats2, :shell, :parse, :sync, :none]

    validate do | value |
      # we can recieve input in following format :
      # As a string -> integer/hex or label
      # As an integer
      # As an hex
      # DO NOT USE value.class -> seems to evaluate to Object instead of class type
      # http://stackoverflow.com/questions/15346324/case-statement-evaluating-class-not-working-as-expected
      case value
      when Fixnum
        if value < -1 or value > 0b1111111111111111
          raise ArgumentError, "property loglevel must be between -1 and 65536/0xffff - #{value} given. See man slapd-config"
        end
      when String
        case value
        when /^0x[0-9a-fA-F]+$/
         if value.to_i(16) < -1 or value.to_i(16) > 0b1111111111111111
           raise ArgumentError, "property loglevel must be between -1 and 65536/0xffff - #{value} given. See man slapd-config"
         end
        when /^[0-9]+$/
          if value.to_i < -1 or value.to_i > 0b1111111111111111
            raise ArgumentError, "property loglevel must be between -1 and 65536/0xffff - #{value} given. See man slapd-config"
          end
        else
          if !(loglevels.include?(value.downcase.to_sym))
            raise ArgumentError, "loglevel attribute #{value} not supported. See man slapd-config"
          end
        end
        # Still not clear when things are converted to symbols ...  But we validate the defaultto also
      when Symbol
        if !(loglevels.include?(value))
          raise ArgumentError, "loglevel attribute #{value} not supported. See man slapd-config"
        end
      end
    end

    # we represent all in symbols if labels are given, else we translate everything in decimal intigers
    munge do | value |
      case value
      when String
        case value
        when /^0x[0-9a-fA-F]+$/,/^[0-9]+$/
          Integer(value)
        else
          # let the default munging happen
          super value.downcase
        end
      else
        value
      end
    end

  end

  newproperty(:authzregexp, :array_matching => :all) do
    desc "An array of authz-regexps"
  end

  #
  # int_properties
  #

  newproperty(:concurrency) do
    desc "Specify  a  desired  level  of  concurrency."
    # if 0, this attirbute will not be set
    defaultto 0
    munge do |value|
      Integer(value)
    end
  end
  newproperty(:connmaxpending) do
    desc "Specify  the  maximum  number  of pending requests for an anonymous session."
    defaultto 100
    munge do |value|
      Integer(value)
    end
  end
  newproperty(:connmaxpendingauth) do
    desc "Specify the maximum number of pending requests for an authenticated session."
    defaultto 1000
    munge do |value|
      Integer(value)
    end
  end
  newproperty(:idletimeout) do
    desc "Specify the number of seconds to wait before forcibly closing an idle client connection."
    # A setting of 0 disables this feature
    defaultto 0
    munge do |value|
      Integer(value)
    end
  end
  newproperty(:indexsubstrifmaxlen) do
    desc "Specify  the  maximum  length  for  subinitial  and  subfinal  indices."
    defaultto 4
    munge do |value|
      Integer(value)
    end
  end
  newproperty(:indexsubstrifminlen) do
    desc "Specify  the  minimum length for subinitial and subfinal indices."
    defaultto 2
    munge do |value|
      Integer(value)
    end
  end
  newproperty(:indexsubstranylen) do
    desc "Specify the length used for subany indices."
    defaultto 4
    munge do |value|
      Integer(value)
    end
  end
  newproperty(:indexsubstranystep) do
    desc "Specify the steps used in subany index lookups."
    defaultto 2
    munge do |value|
      Integer(value)
    end
  end
  newproperty(:indexintlen) do
    desc "Specify  the  key  length for ordered integer indices."
    defaultto 4
    munge do |value|
      Integer(value)
    end
  end
  newproperty(:localssf) do
    desc "Specifies  the  Security  Strength  Factor  (SSF) to be given local LDAP sessions"
    defaultto 71
    munge do |value|
      Integer(value)
    end
  end
  newproperty(:sockbufmaxincoming) do
    desc "Specify the maximum incoming LDAP PDU size for anonymous sessions"
    defaultto 262143
    munge do |value|
      Integer(value)
    end
  end
  newproperty(:sockbufmaxincomingauth) do
    desc "Specify the maximum incoming LDAP PDU size for authenticated sessions"
    defaultto 4194303

    munge do |value|
      Integer(value)
    end

  end
  newproperty(:threads) do
    desc "Specify the maximum size of the primary thread pool."
    defaultto 16

    validate do |value|
      if Integer(value) < 2
        raise ArgumentError, "Value of property \"threads\" must be equal or greater than 2"
      end
    end

    munge do |value|
      Integer(value)
    end

  end
  newproperty(:toolthreads) do
    desc "Specify the maximum number of threads to use in tool mode."
    defaultto 1
    munge do |value|
      Integer(value)
    end
  end
  newproperty(:writetimeout) do
    desc "Specify the number of seconds to wait before forcibly closing a connection with an outstanding write."
    # a setting of '0' disables this function
    defaultto 0
    munge do |value|
      Integer(value)
    end
  end

  #
  # path_properties
  #

  newproperty(:logfile) do
    desc "Specify  a  file  for recording debug log messages."
    defaultto "stderr"
    validate do | value |
      if ! (value =~ /^std/)
        unless Pathname.new(value).absolute?
          fail("Invalid logfile given - Absolute path required - given #{value}")
        end
      end
    end
  end

  newproperty(:argsfile) do
    desc 'The (absolute) name of a file that will hold the slapd servers command line (program name and
              options).'
    defaultto "/var/run/openldap/slapd.args"
    validate do | value |
      unless Pathname.new(value).absolute?
        fail("Invalid argsfile given - Absolute path required - given #{value}")
      end
    end
  end

  newproperty(:pidfile) do
    desc "The (absolute) name of a file that will hold the slapd servers process ID"
    defaultto "/var/run/openldap/slapd.pid"
    validate do | value |
      unless Pathname.new(value).absolute?
        fail("Invalid pidfile given - Absolute path required - given #{value}")
      end
    end
  end

  newproperty(:tlscertificatefile) do
    desc "Specifies the file that contains the slapd server certificate."
    defaultto "/etc/openldap/certs/openldap.pem"
    validate do | value |
      unless Pathname.new(value).absolute?
        fail("Invalid tlscertificatefile given - Absolute path required - given #{value}")
      end
    end
  end

  newproperty(:tlscertificatekeyfile) do
    desc "Specifies the file that contains the slapd server private key that matches the certificate stored in the olcTLSCertificateFile file"
    defaultto "/etc/openldap/certs/password"
    validate do | value |
      unless Pathname.new(value).absolute?
        fail("Invalid tlscertificatekeyfile given - Absolute path required - given #{value}")
      end
    end
  end

  newproperty(:configdir) do
    desc "The (absolete) path of the directory where the dynamic configuration files reside"
    defaultto "/etc/openldap/slapd.d"
    validate do | value |
      unless Pathname.new(value).absolute?
        fail("Invalid configdir given - Absolute path required - given #{value}")
      end
    end
  end

  newproperty(:configfile) do
    desc "Obslote, and not used by in dynamic ldap configuration"
    defaultto "/etc/openldap/slapd.conf.bak"
    validate do | value |
      unless Pathname.new(value).absolute?
        fail("Invalid configfile given - Absolute path required - given #{value}")
      end
    end
  end

  #
  # bool_properties
  #
  # When setting defaultto vaules, use Symbols to make it work, otherwise, null will be returned
  #

  newproperty(:gentlehup, :boolean => true, :parent => Puppet::Property::Boolean) do
    desc 'A  SIGHUP signal will only cause a "gentle" shutdown-attempt'
    defaultto :false
  end
  newproperty(:readonly, :boolean => true, :parent => Puppet::Property::Boolean) do
    desc "This option puts the database into \"read-only\" mode. Any attempts to modify the database will return an \"unwilling to perform\" error"
    defaultto :false
  end
  newproperty(:reverselookup, :boolean => true, :parent => Puppet::Property::Boolean) do
    desc "Enable/disable client name unverified reverse lookup"
    defaultto :false
  end

  #
  # olist_properties
  #

  newproperty(:allows, :parent => Puppet::Property::List) do
    desc "Specify  a set of features to allow (default none)."
    defaultto :none
    newvalues(:none, :bind_v2, :bind_anon_cred, :bind_anon_dn, :update_anon, :proxy_authz_anon)

    def membership
      :allow_membership
    end
  end

  newproperty(:disallows, :parent => Puppet::Property::List) do
    desc "Specify  a set of features to disallow"
    defaultto :none
    newvalues(:none, :bind_anon, :bind_simple, :tls_2_anon, :tls_authc)

    def membership
      :disallow_membership
    end

  end

  # needed for the List -- parent modules ....
  newparam(:membership) do
    desc "Whether specified values should be considered the **complete list**
          (`inclusive`) or the **minimum list** (`minimum`). Defaults to `inclusive`."
    newvalues(:inclusive, :minimum)
    defaultto :inclusive
  end

  newparam(:allow_membership) do
    desc "Whether specified values for the allow attribute should be considered the **complete list**
          (`inclusive`) or the **minimum list** (`minimum`). Defaults to `inclusive`."
    newvalues(:inclusive, :minimum)
    defaultto :inclusive
  end

  newparam(:disallow_membership) do
    desc "Whether specified values for the disallow attribute should be considered the **complete list**
          (`inclusive`) or the **minimum list** (`minimum`). Defaults to `inclusive`."
    newvalues(:inclusive, :minimum)
    defaultto :inclusive
  end
  #
  # list_properties
  #


  #
  # key_properties
  #

  #
  # Parameter entries are grouped here
  #

  newparam( :name , :namevar => true) do
    desc "The ldap config name. should always be config, or config followed wit a number"
    defaultto 'config0'
  end

  newparam( :credential_file ) do
    desc "The file where the login credentials are stored.  This file should be available on the
          ldapserver.  This file should be secured properly.  It should have the following entries
          ldapuser=, ldappassword=, base_dn= and wil override the same params given  in theis type"
  end

  newparam( :force_install ) do
    desc "If set to true, the current openldap configuration directory will be overwritten with the
          archive (zip/tar/tgz,bzip) given in the \'config_archive\' attribute.  This has to be considered
          as a starting point for a fresch openldap configuration.  Id attributes are also  set, these will
          then applied to the fresch installed openldap configuration"
  end

  newparam( :force_restart ) do
    desc "The openldap server will be restarted after all actiosn are performed."
  end

  newparam( :offline ) do
    desc "Perform all actions on an offline openldap server.  If the server is running, it will be stopped,
          All actions will be  performed, and it will be started again.  If the server was already offline,
          it will not be restarted.  Openldap service shoudl be managed with its oen \'Service\' Resource"
  end

  newparam( :ldapuser ) do
    desc "The ldap user to connect to the ldap, with admin rights.  If a credentials file is given, and is accessible,
              then that ldapuser will be used"
  end

  newparam( :ldappassword ) do
    desc "The password to connect to de openldap server.  If a credentials file is given, and is accessible,
          then that password will be used"
  end

  newparam( :base_dn ) do
    desc "The base_dn used to connect to an openldap server.  If a credentials file is given, and is accessible,
           then that base_dn will be used"
  end

  newparam( :encryption ) do
    desc "The encyption to be used for the connection to the ldapserver"
  end

  #
  # Global functions used in the Type definition
  # Code that is needed to help validating the properties and parameters
  #

  def exists?
    provider.exists?
  end
end
