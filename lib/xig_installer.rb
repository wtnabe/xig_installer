# -*- coding: utf-8 -*-
require 'rbconfig'
require 'pathname'
require 'optparse'
require 'erb'
include FileUtils::Verbose
RbConfig = Config unless defined? RbConfig

class XigInstaller
  VERSION    = '0.0.2'
  TARGET_DIR = RbConfig::CONFIG['bindir']
  XIG_GLOB   = '*ig.rb'

  class CommandNotExist < StandardError ; end
  class DirectoryNotExist < StandardError; end
  class NetIRCNotInstalled < StandardError; end
  class TargetGatewayNotValid < StandardError; end
  class TargetGatewayNotInstalled < StandardError; end

  def initialize
    @commands           = nil
    @gateways           = nil
    @gateway_dir        = nil
    @max_cmdname_length = nil
    @target_dir         = TARGET_DIR
  end
  attr_reader :target_dir

  def run
    if ( cmd = parse_args() )
      if ( commands.include?( cmd ) )
        exec_cmd( cmd )
      elsif ( cmd == 'help' )
        usage( ARGV.shift )
      elsif ( cmd =~ /\A(?:--)?version\z/ )
        usage( 'version' )
      end
    else
      usage
    end
  end

  def exec_cmd( cmd )
    if commands.include?( cmd )
      send( "cmd_#{cmd}", *ARGV )
    else
      raise CommandNotExist
    end
  end

  def commands
    if ( !@commands )
      @commands = methods.grep( /\Acmd_(.*)\z/ ).map { |e|
        e.sub( /\Acmd_(.*)\z/, '\1' )
      }
    end

    return @commands
  end

  def installed?( name )
    Dir.chdir( @target_dir ) {
      Dir.glob( XIG_GLOB ).include?( name )
    }
  end

  def different?( name )
    begin
      src = File.stat( File.join( gateway_dir, name ) )
      begin
        dest = File.stat( File.join( @target_dir, name ) )
        if ( src.mtime != dest.mtime )
          return true
        else
          return false
        end
      rescue Errno::ENOENT
        return true
      end
    rescue Errno::ENOENT
      raise NetIRCNotInstalled
    end
  end

  def gateways( dir = nil )
    dir ||= gateway_dir

    if ( dir )
      if ( File.exist?( dir ) )
        Dir.chdir( dir ) {
          Dir.glob( XIG_GLOB )
        }
      else
        raise DirectoryNotExist, dir
      end
    else
      raise NetIRCNotInstalled
    end
  end

  def gateway_dir
    if ( @gateway_dir.nil? )
      net_irc = `gem which net/irc`.chomp

      if ( File.exist?( net_irc ) )
        @gateway_dir = (Pathname( net_irc ).
                         parent.parent.parent + 'examples').to_s
      else
        @gateway_dir = false
      end
    end

    return @gateway_dir
  end

  def cmd_list( subcmd = nil )
    subcmds = methods.grep( /\A_cmd_list_(.*)\z/ ).map { |c|
      c.sub( /\A_cmd_list_(.*)\z/, '\1' )
    }
    if ( subcmd == 'help' )
      subcmds
    elsif ( subcmds.include?( subcmd ) )
      puts send( "_cmd_list_#{subcmd}" )
    else
      puts _cmd_list_available
    end
  end

  def _cmd_list_available
    gateways
  end

  def _cmd_list_installed
    gateways.reject { |e|
      !installed?( e )
    }
  end

  def _cmd_list_update
    _cmd_list_installed.reject { |e|
      !different?( e )
    }
  end

  def cmd_install( *targets )
    available = gateways & targets
    if ( targets.size == 0 )
      _copy( gateways )
    elsif ( available == targets )
      _copy( targets )
    else
      raise TargetGatewayNotValid, (targets - available).join( ', ' )
    end
  end

  def cmd_upgrade( *targets )
    if ( targets.size == 0 )
      _cmd_list_installed.map { |e|
        different?( e ) ? cmd_install( e ).to_s : nil
      }.compact
    else
      targets.reject { |e|
        !installed?( e )
      }.map { |e|
        different?( e ) ? cmd_install( e ).to_s : nil
      }.compact
    end
  end

  def _copy( targets )
    targets.each { |e|
      cp( File.join( gateway_dir, e ), @target_dir, :preserve => true )
    }
  end

  def cmd_uninstall( *targets )
    installed = _cmd_list_installed
    available = installed & targets
    if ( targets.size == 0 )
      _remove( installed )
    elsif ( available == targets )
      _remove( targets )
    else
      raise TargetGatewayNotInstalled, (targets - installed).join( ', ' )
    end
  end

  def _remove( targets )
    targets.each { |e|
      rm( File.join( @target_dir, e ) )
    }
  end

  def usage( cmd = nil )
    puts "#{self.class} ver.#{VERSION}"
    if ( commands.include?( cmd ) )
      puts "\n"
      puts send( "usage_#{cmd}" )
    elsif ( cmd == 'version' )
      ;
    else
      puts ERB.new( <<EOD, nil, '-' ).result( binding )

Usage: #{File.basename( $0 )} command [options] [TARGET]

Commands:
<%- commands.sort.each do |e| -%>
  <%= simple_help( e ) %>
<%- end -%>

Options:
<%= parser.help.sub( /[\r\n]/, '' ) %>
EOD
    end
    exit
  end

  def usage_list( subcmd = nil )
    ERB.new( <<EOD, nil, '-' ).result( binding )
show gateway list

Usage: #{File.basename( $0 )} list [subcommand]

Subcommands:
<%- cmd_list( 'help' ).sort.each do |cmd| -%>
  <%= cmd %>
<%- end -%>
EOD
  end

  def usage_install
    ERB.new( <<EOD ).result( binding )
install specified or all gateways
EOD
  end

  def usage_upgrade
    ERB.new( <<EOD ).result( binding )
upgrade specified or all gateways if need
EOD
  end

  def usage_uninstall
    ERB.new( <<EOD ).result( binding )
uninstall specified or all gateways
EOD
  end

  def simple_help( cmd )
    if ( commands.include?( cmd ) )
      return sprintf( "%-*s   %s",
                      max_cmdname_length,
                      cmd,
                      send( "usage_#{cmd}" ).lines.first.chomp )
    end
  end

  def max_cmdname_length
    if ( !@max_cmdname_length )
      @max_cmdname_length = commands.map { |e|
        e.size
      }.max
    end

    return @max_cmdname_length
  end

  def parse_args
    parser.parse!( ARGV )
    return ARGV.shift
  end

  def parser
    return OptionParser.new { |opt|
      opt.banner = ''
      opt.on( '-t', '--target DIR', 'target directory' ) { |d|
        dir = File.expand_path( d )
        if ( File.exist?( dir ) and File.directory?( dir ) )
          @target_dir = dir
        else
          raise DirectoryNotExist, d
        end
      }
      opt.on( '-g', '--gateway DIR', 'gateway source directory' ) { |d|
        dir = File.expand_path( d )
        if ( File.exist?( dir ) and File.directory?( dir ) )
          @gateway_dir = dir
        else
          raise DirectoryNotExist, d
        end
      }
    }
  end
end

if ( !String.respond_to?( :lines ) )
  class String
    def lines
      self.split( /(?:\r\n|[\r\n])/ )
    end
  end
end
