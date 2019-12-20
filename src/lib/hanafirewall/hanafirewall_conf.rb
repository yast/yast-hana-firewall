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
# Author: Peter Varkoly <varkoly@suse.com>

require "yast"
require "open3"
require "pathname"
require "hanafirewall/sysconfig_editor"
require "y2firewall/firewalld"

Yast.import "Service"

module HANAFirewall
  # get_hana_service_names returns all service short names.
  def get_service_names
    Dir.glob("/etc/hana-firewall/*").map do |path|
      file_name = Pathname.new(path).basename.to_s

      # The firewall program calculates short name by keeping numbers and letters,
      # write '-' for other characters, and convert the whole string into lower case.
      short_name = ""
      file_name.each_codepoint do |c|
        short_name += if /\p{L}/.match(c.chr)
          c.chr
        elsif /\p{N}/.match(c.chr)
          c.chr
        else
          "-"
        end
      end
      short_name.downcase
    end
  end

  # get_inst_numbers retrieves the string array value from HANA_INSTANCE_NUMBERS configuration key.
  def get_inst_numbers
    HANAFirewall::SysconfigEditor.new(IO.read("/etc/sysconfig/hana-firewall"))
      .get("HANA_INSTANCE_NUMBERS").split(/\s+/)
  end

  # set_inst_numbers writes down a new string array value into
  # HANA_INSTANCE_NUMBERS configuration key.
  def set_inst_numbers(new_array)
    conf = HANAFirewall::SysconfigEditor.new(IO.read("/etc/sysconfig/hana-firewall"))
    conf.set("HANA_INSTANCE_NUMBERS", new_array.sort.join(" "))
    IO.write("/etc/sysconfig/hana-firewall", conf.to_text)
  end

  # get_zone_services returns all zone names and their corresponding service names.
  def get_zone_services
    ::Y2Firewall::Firewalld.instance.read
    Hash[
        ::Y2Firewall::Firewalld.instance.zones.map do |zone|
          [zone.name, zone.services]
        end
    ]
  end

  # call the command line program to regenerate service definition files.
  def regen_svcs
    _, status = Open3.capture2e("hana-firewall", "generate-firewalld-services")
    raise "Command line error - " + outerr.gets if status.exitstatus != 0
  end
end
