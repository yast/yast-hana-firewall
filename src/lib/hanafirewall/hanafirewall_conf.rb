# encoding: utf-8
# ------------------------------------------------------------------------------
# Copyright (c) 2016 SUSE LINUX GmbH, Nuernberg, Germany.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 3 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, contact SUSE Linux GmbH.
#
# ------------------------------------------------------------------------------
# Author: Howard Guo <hguo@suse.com>

require 'yast'
require 'open3'
require 'pathname'
require 'socket'
require 'hanafirewall/sysconfig_editor'

Yast.import 'Service'

module HANAFirewall
    # An implementation of .match(string)bool interface that makes use of a regex.
    class PortRegexMatcher
        def initialize(regex)
            @regex = regex
        end

        attr_reader(:regex)

        def ==(other)
            return other.class == self.class && other.regex == @regex
        end

        def match(str)
            return @regex.match(str) != nil
        end
    end

    # An implementation of .match(string)bool interface that tests the integer in string is within a specified range.
    # The numeric range is inclusive on both ends.
    class PortRangeMatcher
        def initialize(begin_num, end_num)
            @begin_num = begin_num
            @end_num = end_num
        end

        attr_reader(:begin_num, :end_num)

        def ==(other)
            return other.class == self.class && other.begin_num == @begin_num && other.end_num == @end_num
        end

        def match(str)
            istr = str.to_i
            return istr <= @end_num && istr >= @begin_num
        end
    end

    # Interpret definitions of HANA and standard system network services.
    # It is usually not necessary to initialise more than one instance of the class.
    class ServiceDefinitions
        def initialize
            # System standard service name VS {:tcp => [matchers], :udp => [matchers]}
            @std_svcs = std_svc_definitions
            # HANA-defined service name VS {:tcp => [matchers], :udp => [matchers]}
            @hana_svcs = hana_svc_definitions
        end

        attr_reader(:std_svcs, :hana_svcs)

        # Construct a port matcher instance from the input string, which is taken from HANA service definition file.
        def port_field_to_matcher(field_str)
            # The port number "definition" may allow instance number subsitution
            if field_str.include?('__INST_NUM+1__')
                return PortRegexMatcher.new(Regexp.new('^' + field_str.gsub('__INST_NUM+1__', '[0-9]{2}') + '$'))
            elsif field_str.include?('__INST_NUM__')
                return PortRegexMatcher.new(Regexp.new('^' + field_str.gsub('__INST_NUM__', '[0-9]{2}') + '$'))
            elsif field_str.include?(':')
                # It can be a numeric range too
                return PortRangeMatcher.new(field_str.split(':')[0].to_i, field_str.split(':')[1].to_i)
            else
                return PortRegexMatcher.new(Regexp.new('^' + field_str + '$'))
            end
        end

        # Interpret a service definition file text and return tuple of two arrays.
        # The first array consists of port matchers that will match TCP ports of the service, one regex per port.
        # The second array consists of similar regexes but for UDP ports.
        def interpret_svc_definition(text)
            tcp = []
            udp = []
            conf = HANAFirewall::SysconfigEditor.new(text)
            tcp_defs = conf.get('TCP')
            if tcp_defs != nil
                tcp_defs.split(/\s+/).each {|field|
                    matcher = port_field_to_matcher(field)
                    tcp << matcher
                }
            end
            udp_defs = conf.get('UDP')
            if udp_defs != nil
                udp_defs.split(/\s+/).each {|field|
                    matcher = port_field_to_matcher(field)
                    udp << matcher
                }
            end
            return [tcp, udp]
        end


        # Interpret all definition files in /etc/hana-firewall.d and return a mapping of
        # HANA service name to TCP and UDP ports (regexes), each of which is a hash key.
        # Either or both of the port arrays may be empty.
        def hana_svc_definitions
            ret = {}
            hana_service_names.each{ |name|
                tcp, udp = interpret_svc_definition(IO.read('/etc/hana-firewall.d/' + name))
                ret[name] = {:tcp => tcp, :udp => udp}
            }
            return ret
        end

        # Interpret all definitions in /etc/services and return a mapping of service name to
        # TCP and UDP ports (port matchers), each of which is a hash key. Either of the port arrays
        # may be empty.
        # The function deliberately avoid calling NSS because HANA firewall starts very early
        # in the boot sequence.
        def std_svc_definitions
            ret = {}
            IO.readlines('/etc/services').each { |line|
                # Lint input lines to remove invalid utf sequences if there is any
                fields = /^([A-Za-z0-9_-]+)\s+([0-9]+)\/(tcp|udp)/.match(line.b)
                if fields != nil
                    svc_name = fields[1]
                    port_num_str = fields[2]
                    prot = fields[3].to_sym
                    if ret[svc_name] == nil
                        ret[svc_name] = {:tcp => [], :udp => []}
                    end
                    ret[svc_name][prot] << port_field_to_matcher(port_num_str)
                end
            }
            return ret
        end

        # Return nil if the port does not belong to any standard or HANA services;
        # Otherwise, return a tuple:
        # - :std or :hana
        # - Service name
        # The search process favours HANA services over standard system services.
        def find_port(number, prot)
            number = number.to_s
            name = nil
            type = nil
            # Try finding a match among HANA services
            @hana_svcs.each { |hana_name, matchers_hash|
                if matchers_hash[prot].any?{|matcher| matcher.match(number)}
                    name = hana_name
                    type = :hana
                    break
                end
            }
            # Try finding a match among standard services
            if type == nil
                @std_svcs.each { |std_name, matchers_hash|
                    if matchers_hash[prot].any?{|matcher| matcher.match(number)}
                        name = std_name
                        type = :std
                        break
                    end
                }
            end
            if name == nil
                return nil
            end
            return [type, name]
        end

        # Return file name of all HANA service definitions, excluding the special one 'HANA_*'.
        def hana_service_names
            # By convention the service definitons are all in capital letters
            return (Dir.glob('/etc/hana-firewall.d/[A-Z]*').map{ |path| Pathname.new(path).basename.to_s}).sort
        end
    end
    ServiceDefinitionsInst = ServiceDefinitions.new

    # Manipulate HANA firewall daemon and configuration.
    class HANAFirewallConf
        include Yast::I18n
        include Yast::Logger

        def initialize
            textdomain 'hanafirewall'
            # SID + instance number combinations
            @hana_sys = []
            # If SSH should be allowed on all interfaces
            @open_ssh = false
            # Services enabled on individual interfaces
            @ifaces = {}
            # Sysconfig editor
            @sysconf = nil
        end

        attr_accessor(:hana_sys, :open_ssh, :ifaces)

        # Call hana-firewall (external program) with the specified parameters, return and log combined stdout/stderr output and exit status.
        def call_hanafw_and_log(*params)
            begin
                out, status = Open3.capture2e('hana-firewall', *params)
                log.info "hana-firewall command - #{params.join(' ')}: #{status} #{out}"
                return out, status.exitstatus
            rescue Errno::ENOENT
                log.error 'hana-firewall command does not exist'
                return '', 127
            end
        end

        # Break down text of /etc/sysconfig/hana-firewall file.
        def load(text)
            @sysconf = HANAFirewall::SysconfigEditor.new(text)
            # SID + instance number combinations
            @hana_sys = @sysconf.get('HANA_SYSTEMS').split(/\s+/)
            # If SSH should be allowed on all interfaces
            @open_ssh = @sysconf.get('OPEN_ALL_SSH') == 'yes'
            # Services enabled on individual interfaces
            # It eventually looks like {"eth0" => {"smtp" => "10.0.0.1", "finger" => "0.0.0.0/0"}}
            @ifaces = {}
            # Collect interface numbers
            iface_num = {}
            (0..@sysconf.array_len('INTERFACE') - 1).each{ |num|
                iface_name = @sysconf.array_get('INTERFACE', num)
                if iface_name != ''
                    iface_num[num.to_i] = iface_name
                    @ifaces[iface_name] = {}
                end
            }
            # Collect interface services
            @sysconf.scan(/INTERFACE_[0-9]+_SERVICES/) { |key, _, val|
                iface_name = iface_num[/([0-9]+)/.match(key)[0].to_i]
                svcs = @ifaces[iface_name]
                if svcs != nil
                    val.split(/\s+/).each{ |svc_def|
                        # Value is a space-separated list of service names, optionally come with an IP address or CIDR.
                        svc_and_cidr = svc_def.split(/:/)
                        if svc_and_cidr.length == 1
                            svcs[svc_and_cidr[0]] = '0.0.0.0/0'
                        else
                            svcs[svc_and_cidr[0]] = svc_and_cidr[1]
                        end
                    }
                    @ifaces[iface_name] = svcs
                end
                [:continue]
            }
        end

        # Return latest text for the configuration file /etc/sysconfig/hana-firewall.
        def to_text
            @sysconf.set('HANA_SYSTEMS', @hana_sys.sort.join(' '))
            @sysconf.set('OPEN_ALL_SSH', @open_ssh ? 'yes' : 'no')
            @open_ssh = @sysconf.get('OPEN_ALL_SSH') == 'yes'
            @sysconf.array_resize('INTERFACE', @ifaces.length)
            # Reconstruct all INTERFACE_xx and INTERFACE_xx_SERVICES keys
            @sysconf.scan(/INTERFACE/) { |_, _, _|
                [:delete_continue]
            }
            @sysconf.scan(/INTERFACE_[0-9]+_SERVICES/) { |_, _, _|
                [:delete_continue]
            }
            # Remove all interfaces that do not run service
            @ifaces.delete_if{|_, svcs| svcs.length == 0}
            iface_keys = @ifaces.keys
            (0..iface_keys.length-1).each{ |i|
                iface_name = iface_keys[i]
                @sysconf.array_set('INTERFACE', i, iface_name)
                # Construct service string is more complicated:
                # - Omit CIDR or IP address if it is 0.0.0.0
                # - Otherwise, concatenate the address with service name, after a colon.
                svc_value = @ifaces[iface_name].map{ |name, cidr|
                    if cidr == '0.0.0.0' || cidr == '0.0.0.0/0'
                        name
                    else
                        "#{name}:#{cidr}"
                    end
                }.join(' ')
                @sysconf.set("INTERFACE_#{i}_SERVICES", svc_value)
            }
            return @sysconf.to_text
        end

        # Return status of HANA firewall, return true only if firewall status is activated and OK.
        def state
            _, status = call_hanafw_and_log('status')
            if status == 0
                return true
            end
            return false
        end

        # Enable+start or disable+stop hana firewall and its daemon (hana-firewall.service).
        # It may take up to a minute to enable+start the daemon.
        # Return boolean status and debug output (only in error case).
        # Boolean status is true only if the operation is carried out successfully.
        def set_state(enable)
            if enable
                if !Yast::Service.Enable('hana-firewall')
                    return false, 'failed to enable hana-firewall service'
                end
                if !Yast::Service.Start('hana-firewall')
                    return false, 'failed to start hana-firewall service'
                end
                out, status = call_hanafw_and_log('apply')
                if status != 0
                    return false, out
                end
            else
                out, status = call_hanafw_and_log('unapply')
                if status != 0
                    return false, out
                end
                if !Yast::Service.Stop('hana-firewall')
                    return false, 'failed to stop hana-firewall service'
                end
                if !Yast::Service.Disable('hana-firewall')
                    return false, 'failed to disable hana-firewall service'
                end
            end
            return true, ''
        end

        # Save configuration file.
        def apply
            IO.write('/etc/sysconfig/hana-firewall', to_text)
        end

        # Get the list of listening ports on the system and look for them among HANA services.
        # Return array of HANA services that correspond to the listening ports.
        def running_hana_services
            hana_svcs = []
            collect_func = lambda { |prot|
                lambda { |line|
                    fields = line.split(/\s+/)
                    # Local address is 0.0.0.0 and status is Listening
                    if /^00000000:/.match(fields[2]) && fields[4] == '0A'
                        # Port is the hex string following colon in the local address field
                        port_name = ServiceDefinitionsInst.find_port(fields[2].split(/:/)[1].to_i(16), :tcp)
                        # Only collect HANA service names
                        if port_name != nil && port_name[0] == :hana
                            hana_svcs << port_name[1]
                        end
                    end
                }
            }

            # Drop the header line
            IO.readlines('/proc/net/tcp').drop(1).each &collect_func.call(:tcp)
            IO.readlines('/proc/net/udp').drop(1).each &collect_func.call(:udp)
            return hana_svcs
        end

        # Look for HANA instances that are currently installed on this computer.
        # Return an array of strings, each string comprises HANA SID and instance number.
        def hana_instance_names
            ret = []
            Dir.glob('/usr/sap/*/HDB*').each { |hdbpath|
                path = Pathname.new(hdbpath)
                # Instance number is a double digit integer
                instance_num = path.basename.to_s.gsub(/^HDB/, '')
                # SID is a three letter string
                sid = path.dirname.basename.to_s
                if sid.length == 3
                    ret << sid.upcase + instance_num
                end
            }
            return ret
        end

        # Return name of all network interfaces that are eligible for participating in HANA firewall.
        def eligible_ifaces
            all_iface_names = Socket.getifaddrs.map{|iface| iface.name}
            all_iface_names.delete_if{|name| /lo.*/.match(name)}
            return all_iface_names.uniq.sort
        end

        # Look for running HANA systems and inspect currently listening ports, generate a configuration
        # that opens all of the ports on all interfaces, then merge the generated configuration with the
        # existing configuration.
        # The return value will be a hash of four keys:
        # * :hana_sys - correspond to class attribute
        # * :open_ssh - correspond to class attribute
        # * :ifaces - correspond to class attribute
        # * :new_svcs - list of new service names discovered and enabled in the generated config
        def gen_config
            new_hana_sys = (@hana_sys.clone + hana_instance_names).uniq.sort
            if new_hana_sys.length == 0
                # If HANA is not even installed, do not propose anything new, return config as-is.
                return {:hana_sys => new_hana_sys, :open_ssh => @open_ssh, :ifaces => @ifaces.clone, :new_svcs => []}
            end
            # The proposal will not alter SSH status
            new_open_ssh = @open_ssh
            # Inform caller about newly discovered service names
            new_svcs = []
            # Generate new configuration on top of existing configuration
            new_ifaces = @ifaces.clone
            running_svcs = running_hana_services
            running_ha = running_svcs.include?('HANA_HIGH_AVAILABILITY')
            # Prepare to open new services on all interfaces
            eligible_ifaces.each{ |iface|
                new_iface_svcs = {}
                # Merge interface services against existing configuration
                existing = @ifaces[iface]
                if existing != nil
                    new_iface_svcs.merge!(existing)
                end
                running_svcs.each{|svc|
                    if new_iface_svcs[svc] == nil
                        new_iface_svcs[svc] = '0.0.0.0/0'
                        new_svcs << svc
                    end
                }
                if new_iface_svcs.length > 0
                    # If HA is involved, make sure database clients can connect even though those ports are not yet listening
                    if running_ha
                        if !new_iface_svcs.has_key?('HANA_DATABASE_CLIENT')
                            new_iface_svcs['HANA_DATABASE_CLIENT'] = '0.0.0.0/0'
                            new_svcs << 'HANA_DATABASE_CLIENT'
                        end
                        if !new_iface_svcs.has_key?('HANA_SYSTEM_REPLICATION')
                            new_iface_svcs['HANA_SYSTEM_REPLICATION'] = '0.0.0.0/0'
                            new_svcs << 'HANA_SYSTEM_REPLICATION'
                        end
                    end
                    new_ifaces[iface] = new_iface_svcs
                end
            }
            return {:hana_sys => new_hana_sys, :open_ssh => new_open_ssh, :ifaces => new_ifaces, :new_svcs => new_svcs.uniq.sort}
        end

        # Save current configuration to /etc/sysconfig/hana-firewall.
        def save_config
            IO.write('/etc/sysconfig/hana-firewall', to_text)
        end
    end
    HANAFirewallConfInst = HANAFirewallConf.new

    # Hold autoyast-specific state information and bridge the action between autoyast and HANAFirewallConf.
    class HANAFirewallAutoconf
        include Yast::I18n
        include Yast::Logger

        def initialize
            textdomain 'hanafirewall'
            @enable = false
            @open_ssh = false
        end

        # If @enable is true, automatically configure HANA firewall and enable it.
        # Otherwise, disable HANA firewall.
        # Return tuple of boolean status and command output (only in error case).
        # Boolean status is true only if all operations are carried out successfully.
        def apply
            HANAFirewallConfInst.load(IO.read('/etc/sysconfig/hana-firewall'))
            if @enable
                HANAFirewallConfInst.open_ssh = @open_ssh
                new_conf = HANAFirewallConfInst.gen_config
                HANAFirewallConfInst.hana_sys = new_conf[:hana_sys]
                HANAFirewallConfInst.ifaces = new_conf[:ifaces]
                HANAFirewallConfInst.save_config
                return HANAFirewallConfInst.set_state(true)
            end
            return HANAFirewallConfInst.set_state(false)
        end

        attr_accessor(:enable, :open_ssh)
    end
    HANAFirewallAutoconfInst = HANAFirewallAutoconf.new
end
