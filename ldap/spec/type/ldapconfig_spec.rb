require 'spec_helper'
require 'pry'

describe Puppet::Type.type(:ldapconfig) do
  before :each do
    @provider_class = described_class.provide(:simple) do
      # has_features :feature1 :feature2
      mk_resource_methods
      def create; end
      def delete; end
      def exists?; get(:ensure) != :absent; end
      def flush; end
      def self.instances; []; end
    end
    described_class.stub(:defaultprovider).and_return @provider_class
  end

  it "should be able to create an instance" do
    described_class.new(:name => 'config0').should_not be_nil
  end

  # if some features are defined,  this can be tested as follow :
  # it "should have a feature1 feature"
  #   describe_class.provider_feature(:feature1).should_not be_nil
  # end


  # testing that the existence of some value is asked to the provider code
  # but since this is coded in  the provider tree, and multiple providers
  # could be present, this is mocked/stubbed (?) in the before block.  Here
  # we tests only the invoking of the provider's existence code in the instance

  describe "instances" do
    it "should delegete existence questions to its provider" do
      # create a dummy provider
      @provider = @provider_class.new(:name => 'config', :ensure => :absent)
      # create a dummy instance, and assign above provider to it
      instance = described_class.new(:name => 'config', :provider => @provider)

      # set the variable the provider should return
      @provider.set(:ensure => :present)
      instance.exists?.should == true
      end
  end

  # one way to check the existance of all properties and params, grouped in this cast by
  # the differnt type of properties, see /usr/share/ruby/vendor_ruby/puppet/property for a list
  # currently : boolean ; ensure ; keyvalue ; list ; orderdlist ....
  # see also /usr/share/ruby/vendor_ruby/puppet/property.rb

  string_properties = [ :attributeoptions, :saslsecprops, :tlsverifyclient, :loglevel, :authzregexp ]
  int_properties  =   [ :concurrency, :connmaxpending,
                        :connmaxpendingauth, :idletimeout, :indexsubstrifmaxlen, :indexsubstrifminlen,
                        :indexsubstranylen, :indexsubstranystep, :indexintlen, :localssf, :sockbufmaxincoming,
                        :sockbufmaxincomingauth, :threads, :toolthreads, :writetimeout ]
  path_properties =   [ :logfile, :argsfile, :pidfile, :tlscertificatekeyfile, :tlscertificatefile,
                        :configdir, :configfile ]
  bool_properties =   [ :gentlehup, :readonly, :reverselookup ]
  olist_properties  = [ :allows, :disallows ]
  list_properties   = []
  key_properties    = []


  # this checks are for all defined properties.  The forst block  applies to all properties,
  # Then the different properties groups are checked for specific things.
  #
  describe "testing all desired properties are declared and documented" do
    (int_properties + bool_properties + path_properties + string_properties + olist_properties + list_properties + key_properties).each do | property |
      #
      # check if a Puppet::Property derived class is defined for the property
      #
      it "should have a #{property} property" do
        described_class.attrclass(property).ancestors.should be_include(Puppet::Property)
      end
      #
      # test if a doc string is defined inside the property instance
      #
      it "should have documentation for its #{property} property" do
        described_class.attrclass(property).doc.strip.should_not == ""
      end
    end
  end

  #
  # Checking the int_properties, they return an integer value, even when a decimal string is provided
  #
  describe "testing the integer type properties" do
    int_properties.each do | property|
      it "should return integer for default property #{property}" do
        described_class.new(:name => 'config0')[property].should be_instance_of(Fixnum)
      end
      it "should return integer whith integer for property #{property}" do
        described_class.new(:name => 'config0', property => 10)[property].should == 10
      end
      it "should return integer whith number string for property #{property}" do
        described_class.new(:name => 'config0', property => "10")[property].should == 10
      end
      it "should raise error with non-number string for property #{property}" do
        expect { described_class.new(:name => 'config0', property => "wrong") }.to raise_error
      end
    end
  end

  describe "Testing validation :threads property" do
    it "should raise error when value is lower than 2" do
      expect { described_class.new(:name => 'config0', :threads => 1) }.to raise_error
    end
    it "should raise error when number string lower than 2" do
      expect { described_class.new(:name => 'config0', :threads => "1") }.to raise_error
    end
  end

  #
  # Checking for  specific Puppet::Properties types
  #

  # The Puppet::Property::Boolean uses the Puppet::Coercion
  # which  accept the follwing formats for
  # true  = true, :true, 'true', :yes, 'yes'
  # false = false, :false, 'false', :no, 'no'
  # We do not have to test those values, we are using already proven/tested code for that
  # We only test if it raises an error if somethinhg else is give
  #
  # And it does raise an error if no bool is given :
  # 'Munging failed for value "0" in class readonly: expected a boolean value'
  # If it does not do that, we have to add our own validation to it, otherwise, we only add defaults
  #
  # We can keep the testing of the default into the loop, since all properties default to FALSE
  describe "testing boolean typed ldap property settings" do
    bool_properties.each do | property |
      it "should have a Boolean #{property}" do
        described_class.attrclass(property).ancestors.should be_include(Puppet::Property::Boolean)
      end
      it "should return the default value if property #{property} is not set" do
        described_class.new(:name => 'config0')[property].should == false
      end
      # Following tests are not needed, but only verify the puppet code does  work and raise error when needed
#      it "should return false if property #{property} is set as string" do
#        described_class.new(:name => 'config0', property => 'FalSE')[property].should == false
#      end
#      it "should raise error if property #{property} is not boolean-like" do
#        expect { described_class.new(:name => 'config0', property => '1') }.to raise_error
#      end
    end
  end

  describe "testing the path properties" do
    path_properties.each do |property|
      it "should return the default value if property #{property} is not set" do
        # we only test if the property is not nill, since the paths will differ for every property
        # It will also raise an error if the defaulto does not pass the validation
        described_class.new(:name => 'config0')[property].should_not == nil
      end
      it "should raise error if property #{property} is not absolute path" do
        expect { described_class.new(:name => 'config0', property => 'not-a-path') }.to raise_error
      end
      it "should return /this/is/an/absolute/path for property #{property} if set" do
         described_class.new(:name => 'config0', property => '/this/is/an/absolute/path')[property].should == '/this/is/an/absolute/path'
      end
    end
  end

  describe "testing of the ordered list properties" do
    olist_properties.each do | property |
      it "should have a ordered_list #{property}" do
        described_class.attrclass(property).ancestors.should be_include(Puppet::Property::OrderedList)
      end
    end
  end

  describe "testing of the unordered list properties" do
    list_properties.each do | property |
      it "should have a list #{property}" do
        described_class.attrclass(property).ancestors.should be_include(Puppet::Property::List)
      end
    end
  end

  describe "testsing of the key-value properties" do
    key_properties.each do | property |
      it "should have a key-values #{property}" do
        described_class.attrclass(property).ancestors.should be_include(Puppet::Property::KeyValue)
      end
    end
  end
  # Type specific common tests that are performed depending on which property type
  # like list, ordered list, keyvalues
end
