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
require 'ui/dialog'
require 'hanafirewall/hanafirewall_conf'
Yast.import 'UI'
Yast.import 'Icon'
Yast.import 'Label'
Yast.import 'Popup'

module HANAFirewall
    # AutoYast main dialog allows user to enable (with auto-config) or disable HANA firewall.
    class AutoMainDialog < UI::Dialog
        include Yast
        include UIShortcuts
        include I18n
        include Logger

        def initialize
            super
            textdomain 'hanafirewall'
        end

        def create_dialog
            return super
        end

        def dialog_options
            Opt(:decoreated, :defaultsize)
        end

        def dialog_content
            VBox(
                Left(HBox(
                    Icon::Simple('yast-firewall'),
                    Heading(_('SAP HANA Firewall Configuration')),
                )),
                VSpacing(1),
                MinWidth(50, HSquash(Frame(_('Global Options'), VBox(
                    Left(CheckBox(Id(:enable_fw), _('Enable Firewall'), HANAFirewallAutoconfInst.enable)),
                    Left(CheckBox(Id(:open_ssh), Opt(:notify), _('Allow Remote Shell Access (SSH)'), HANAFirewallAutoconfInst.open_ssh)),
                )))),
                VSpacing(1),
                Label(_('HANA firewall works on top of SUSE firewall to help securing your network traffic.')),
                Label(_('It will generate configuration for first use according to running HANA instances.')),
                Label(_('More information on HANA firewall can be found in manual page "hana-firewall (8)".')),
                VSpacing(1),
                HBox(
                    PushButton(Id(:help), _('Help')),
                    ButtonBox(
                        PushButton(Id(:ok), Label.OKButton),
                        PushButton(Id(:cancel), Label.CancelButton),
                    ),
                ),
            )
        end

        def open_ssh_handler
            if UI.QueryWidget(Id(:open_ssh), :Value) && !Popup.ContinueCancel(_('"Allow Remote Shell Access" will open SSH access on all network interfaces, is this really intentional?'))
                UI.ChangeWidget(Id(:open_ssh), :Value, false)
            end
        end

        def help_handler
            Popup.LongMessageGeometry(_("HANA firewall works on top of SUSE firewall, to help securing your network traffic.\n" +
"Any service allowed to pass through HANA firewall will override the decision of SUSE firewall.\n\n" +
"You may also administrate HANA firewall using command \"hana-firewall\"\n" +
"See \"man 8 hana-firewall\" for more information on HANA firewall administration.\n\n" +
"Please note that the automatically generated configuration (for first use) only caters for single-tenant HANA installation."
), 60, 16)
        end

        def ok_handler
            HANAFirewallAutoconfInst.open_ssh = UI.QueryWidget(Id(:open_ssh), :Value)
            HANAFirewallAutoconfInst.enable = UI.QueryWidget(Id(:enable_fw), :Value)
            finish_dialog(:finish)
        end

        def cancel_handler
            finish_dialog(:finish)
        end
    end
end
