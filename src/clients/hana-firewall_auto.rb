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
# This source file must use an inconsistent file name due to limitations of YaST.

require 'yast'
require 'installation/auto_client'
require 'hanafirewall/hanafirewall_conf'
require 'hanafirewallui/auto_main_dialog'

module HANAFirewall
    # Automatically generate configuration for HANA firewall and activate it.
    class AutoClient < Installation::AutoClient
        include Yast
        include UIShortcuts
        include I18n
        include Logger

        def initialize
            super
            textdomain 'hanafirewall'
        end

        def run
            progress_orig = Progress.set(false)
            ret = super
            Progress.set(progress_orig)
            ret
        end

        # There is only one bool parameter to import.
        def import(exported)
            HANAFirewallAutoconfInst.enable = exported['enable']
            HANAFirewallAutoconfInst.open_ssh = exported['open_ssh']
            return true
        end

        # There is only one bool parameter to export.
        def export
            return {'enable' => HANAFirewallAutoconfInst.enable, 'open_ssh' => HANAFirewallAutoconfInst.open_ssh}
        end

        # Insignificant to autoyast.
        def modified?
            return true
        end

        # Insignificant to autoyast.
        def modified
            return
        end

        # Return a readable text summary.
        def summary
            text = ''
            if HANAFirewallAutoconfInst.enable
                text = _('HANA firewall will be enabled and configured automatically according to installed SAP HANA instances.')
            else
                text = _('HANA firewall is not enabled.')
            end
            if HANAFirewallAutoconfInst.open_ssh
                text += _('Remote shell access (SSH) will be allowed on all network interfaces.')
            end
            return text
        end

        # Display dialog to let user turn firewall on/off.
        def change
            AutoMainDialog.new.run
            return :finish
        end

        # Read the status of firewall on this system and memorise it as autoyast state.
        def read
            HANAFirewallAutoconfInst.enable = HANAFirewallConfInst.state
            return true
        end

        def write
            success, out = HANAFirewallAutoconfInst.apply
            log.info "HANAFirewall::AutoClient.write: success #{success} output #{out}"
            return success
        end

        def reset
            HANAFirewallAutoconfInst.enable = false
            HANAFirewallAutoconfInst.open_ssh = false
            return true
        end

        def packages
            return {'install' => ['HANA-Firewall'], 'remove' => []}
        end
    end
end

HANAFirewall::AutoClient.new.run
