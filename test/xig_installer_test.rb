require 'rubygems'
require File.dirname(__FILE__) + '/test_helper.rb'

require "test/unit"
class XigInstallerTest < Test::Unit::TestCase
  def setup
    @obj = XigInstaller.new
    begin
      @obj.cmd_uninstall
    rescue
    end
  end

  def teardown
    @obj.cmd_uninstall
  end

  def test_exec_cmd
    c = 'abc'
    assert( !@obj.commands.include?( c ) )
    begin
      assert( @obj.exec_cmd( c ) )
    rescue XigInstaller::CommandNotExist
      assert( true )
    end
  end

  def test_commands
    cmds = @obj.commands
    assert( cmds.is_a?( Array ) )
    assert( cmds.size > 0 )
  end

  def test_installed?
    assert( !@obj.installed?( 'tig.rb' ) )
    @obj.cmd_install( 'tig.rb' )
    assert( @obj.installed?( 'tig.rb' ) )
  end

  def test_gateways
    begin
      require 'net/irc'
      gateways = @obj.gateways
      assert( gateways.is_a?( Array ) )
      assert( gateways.size > 0 )
      gateways.each { |e|
        assert( e =~ /\A.*ig\.rb\z/ )
      }
    rescue LoadError
      assert( !@obj.gateways )
    end
    begin
      @obj.gateways( 'target' )
    rescue XigInstaller::DirectoryNotExist
      assert( true )
    end
  end

  def test_gateway_dir
    begin
      require 'net/irc'
      assert( File.exist?( @obj.gateway_dir ) )
    rescue LoadError
      assert( !@obj.gateway_dir )
    end
  end

  def test_cmd_list
    subcmds = @obj.cmd_list( 'help' )
    assert( subcmds.is_a?( Array ) )
    assert( subcmds.size > 0 )
  end

  def test_cmd_list_available
    availables = @obj._cmd_list_available
    assert( availables.is_a?( Array ) )
    assert( availables.size > 0 )
  end

  def test_cmd_list_installed
    assert( @obj._cmd_list_installed.is_a?( Array ) )
  end

  def test_cmd_list_update
    installed = @obj._cmd_list_installed
    assert( @obj._cmd_list_update.size == installed.size )
  end

  def test_cmd_install
    begin
      @obj.cmd_install( 'foo' )
    rescue XigInstaller::TargetGatewayNotValid
      assert( true )
    end
    assert( tig = @obj.cmd_install( 'tig.rb' ) )
    @obj.cmd_uninstall()
    assert( all = @obj.cmd_install() )
    assert( all.size > tig.size )
  end

  def test_cmd_upgrade
    target = 'tig.rb'
    @obj.cmd_install( target )
    File.utime( File.stat( __FILE__ ).atime,
                File.stat( __FILE__ ).mtime,
                File.join( @obj.target_dir, target ) )
    assert( @obj.different?( target ) )
    assert( @obj.cmd_upgrade( target ) == [target] )
    assert( !@obj.different?( target ) )
    assert( @obj.cmd_upgrade( target ) == [] )
    File.utime( File.stat( __FILE__ ).atime,
                File.stat( __FILE__ ).mtime,
                File.join( @obj.target_dir, target ) )
    assert( @obj.cmd_upgrade() == [target] )
  end

  def test_cmd_uninstall
    @obj.cmd_install( 'tig.rb' )
    assert( tig = @obj.cmd_uninstall( 'tig.rb' ) )
    @obj.cmd_install( 'tig.rb' )
    assert( all = @obj.cmd_uninstall() )
    assert( tig == all )
    assert( @obj.cmd_uninstall() )
    begin
      @obj.cmd_uninstall( 'tig.rb' )
    rescue XigInstaller::TargetGatewayNotInstalled
      assert( true )
    end
    begin
      @obj.cmd_uninstall( 'foo' )
    rescue XigInstaller::TargetGatewayNotInstalled
      assert( true )
    end
   end
  def test_parser
    assert( @obj.parser.parse( %w( help ) ) == %w( help ) )
    assert( @obj.target_dir == RbConfig::CONFIG['bindir'] )
    # -t
    target = (%w( /opt/local/bin /sw/local/bin ) +
              [File.expand_path(File.dirname( __FILE__ ))]).find { |e|
      File.exist?( e )
    }
    @obj.parser.parse( %w( install -t ) + [target] )
    assert( @obj.target_dir == target )
    begin
      @obj.parser.parse( %w( install -t ) + [target] )
    rescue XigInstaller::DirectoryNotExist
      assert( true )
    end
    # -g
    src = (Pathname( __FILE__ ).parent.expand_path).to_s
    @obj.parser.parse( %w( install -g ) + [src] )
    assert( @obj.gateway_dir == src )
  end
end
