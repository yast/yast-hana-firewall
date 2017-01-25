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
Yast.import 'Package'

module HANAFirewall
    # Main dialog allows user to control firewall state and edit the configuration.
    class MainDialog
        include Yast
        include UIShortcuts
        include I18n
        include Logger

        def initialize
            textdomain 'hanafirewall'
        end

        def run
            # Render the dialog
            UI.OpenDialog(Opt(:decoreated, :defaultsize), VBox(
                Left(HBox(
                    Icon::Simple('yast-firewall'),
                    Heading(_('SAP HANA Firewall Configuration')),
                )),
                VBox(
                    # On top there are daemon controls and label showing HANA instance names
                    VSpacing(1.0),
                    # In centre there is the configuration editor
                    VBox(
                        HBox(
                            # Available remaining services and manual entry
                            VBox(
                                Left(Frame(_('Global Options'), VBox(
                                    Left(CheckBox(Id(:enable_fw), _('Enable Firewall'), HANAFirewallConfInst.state)),
                                    Left(CheckBox(Id(:open_ssh), Opt(:notify), _('Allow Remote Shell Access (SSH)'), HANAFirewallConfInst.open_ssh)),
                                ))),
                                HWeight(40, SelectionBox(Id(:avail_svc), _('All HANA services:'))),
                                Left(Label(_("Other service and CIDR (example: https:10.0.0.0/8):"))),
                                HBox(
                                    InputField(Id(:manual_svc), Opt(:hstretch), ""),
                                    PushButton(Id(:add_manual_svc), _("Add →"))
                                )
                            ),
                            # Add/remove
                            HWeight(10, VBox(PushButton(Id(:add_svc), _('→')), PushButton(Id(:del_svc), _('←')))),
                            # Selected services
                            HWeight(40, VBox(
                                Left(ComboBox(Id(:ifaces), Opt(:notify), _('Allowed Services on Network Interface'), [])),
                                SelectionBox(Id(:selected_svc), _('Open ports for these services:'))
                            )),
                        )
                    ),
                ),
                HBox(
                    PushButton(Id(:help), _('Help')),
                    ButtonBox(
                        PushButton(Id(:ok), Label.OKButton),
                        PushButton(Id(:cancel), Label.CancelButton),
                    ),
                ),
            ))

            # Install firewall package
            package_present = Package.Installed('HANA-Firewall')
            if !package_present && Popup.YesNo(_('HANA-Firewall eases the task of setting up network firewall for SAP HANA instances.
Would you like to install and use it now?')) && Package.DoInstall(['HANA-Firewall'])
                package_present = true
            end
            if !package_present
                return :finish_dialog
            end

            # Load configuration for the first interface
            eligible_ifaces = HANAFirewallConfInst.eligible_ifaces
            if eligible_ifaces.length == 0
                Popup.Error(_('Cannot find any network interface that can participate in firewall configuration.
Please check system network configuration.'))
                return :finish_dialog
            end
            UI.ChangeWidget(Id(:ifaces), :Items, eligible_ifaces)

            # If none of the configured HANA instance names exists, then propose to generate a new configuration automatically.
            existing_sys = HANAFirewallConfInst.hana_instance_names
            if HANAFirewallConfInst.hana_sys.length == 0 || existing_sys.any? {|sys| !HANAFirewallConfInst.hana_sys.include?(sys)}
                gen_conf = HANAFirewallConfInst.gen_config
                if gen_conf[:hana_sys].length == 0
                    # HANA is not installed
                    Popup.Error(_('Cannot find an installed SAP HANA. Please install SAP HANA and then re-visit this firewall.'))
                    return :finish_dialog
                end
                if gen_conf[:new_svcs].length > 0
                    # The configuration generator discovered new services, prompt user for approval.
                    prompt = _("The following configuration is automatically generated for this system:\n\n")
                    prompt += _("SAP HANA instances:\n")
                    prompt += gen_conf[:hana_sys].sort.map{|x| ' - ' + x}.join("\n")
                    prompt += _("\nFirewalled network interfaces:\n")
                    prompt += gen_conf[:ifaces].keys.sort.map{|x| ' - ' + x}.join("\n")
                    prompt += _("\nThese services will be allowed on the network interfaces:\n")
                    prompt += gen_conf[:new_svcs].sort.map{|x| ' - ' + x}.join("\n")
                    prompt += _("\n\nDo you agree with the proposal? If not, you can still set up the firewall manually.")
                    if Popup.YesNo(prompt)
                        HANAFirewallConfInst.hana_sys = gen_conf[:hana_sys]
                        HANAFirewallConfInst.ifaces = gen_conf[:ifaces]
                    end
                end
            end
            # If some of the HANA instance names are missing, prompt user to add them
            missing_sys = HANAFirewallConfInst.hana_instance_names - HANAFirewallConfInst.hana_sys
            if missing_sys.length > 0
                if Popup.YesNo(
                    _("The following SAP HANA instances do not yet participate in the firewall setup:\n") +
                    missing_sys.sort.map{|x| ' - ' + x}.join("\n") +
                    _("\n\nWould you like to use firewall on those instances as well?")
                )
                    HANAFirewallConfInst.hana_sys += missing_sys
                end
            end

            refresh_lists

            # Begin the event loop
            begin
                event_loop
            ensure
                UI.CloseDialog
            end
            return :finish_dialog
        end

        # Load service lists.
        def refresh_lists
            iface_name = UI.QueryWidget(Id(:ifaces), :Value)
            selected_svc_hash = HANAFirewallConfInst.ifaces.fetch(iface_name, {})
            selected_svc_list = selected_svc_hash.map{|name, cidr|
                # Display CIDR only if it is not 0.0.0.0/0
                if cidr == '0.0.0.0/0'
                    name
                else
                    "#{name}:#{cidr}"
                end
            }
            avail_svcs = ServiceDefinitionsInst.hana_svcs.keys - selected_svc_hash.keys
            UI.ChangeWidget(Id(:avail_svc), :Items, avail_svcs.sort)
            UI.ChangeWidget(Id(:selected_svc), :Items, selected_svc_list.sort)
            UI.RecalcLayout
        end

        def event_loop
            loop do
                case UI.UserInput
                    when :open_ssh
                        open_ssh = UI.QueryWidget(Id(:open_ssh), :Value)
                        if open_ssh && !Popup.ContinueCancel(_('"Allow Remote Shell Access" will open SSH access on all network interfaces, is this really intentional?'))
                            UI.ChangeWidget(Id(:open_ssh), :Value, false)
                            redo
                        end
                        HANAFirewallConfInst.open_ssh = open_ssh
                    when :ok
                        HANAFirewallConfInst.save_config
                        success, out = HANAFirewallConfInst.set_state(UI.QueryWidget(Id(:enable_fw), :Value))
                        if success
                            Popup.Message(_('HANA firewall configuration has been saved successfully.'))
                        else
                            Popup.ErrorDetails(_('Firewall configuration failed to apply.'), out)
                        end
                        return
                    when :ifaces
                        refresh_lists
                    when :add_svc
                        svc = UI.QueryWidget(Id(:avail_svc), :CurrentItem)
                        iface_name = UI.QueryWidget(Id(:ifaces), :Value)
                        if svc
                            HANAFirewallConfInst.ifaces[iface_name] = HANAFirewallConfInst.ifaces.fetch(iface_name, {}).merge({svc => '0.0.0.0/0'})
                            refresh_lists
                        end
                    when :del_svc
                        # Some services are listed in notation <name>:<cidr>
                        svc = UI.QueryWidget(Id(:selected_svc), :CurrentItem).to_s.split(/:/)
                        iface_name = UI.QueryWidget(Id(:ifaces), :Value)
                        HANAFirewallConfInst.ifaces[iface_name].delete(svc[0])
                        refresh_lists
                    when :add_manual_svc
                        # Validations
                        input = UI.QueryWidget(Id(:manual_svc), :Value).to_s.strip
                        if input == ''
                            redo
                        end
                        svc_cidr = input.split(/:/)
                        if svc_cidr.length != 2
                            Popup.Error(_("Please enter service name and CIDR in form: service_name:CIDR_block"))
                            redo
                        end
                        if !ServiceDefinitionsInst.std_svcs.include?(svc_cidr[0])
                            Popup.Error(_("The service name does not seem to be valid.\n" +
                                "Please read /etc/services for a list of available service names."))
                            redo
                        end
                        # Add to list
                        iface_name = UI.QueryWidget(Id(:ifaces), :Value)
                        HANAFirewallConfInst.ifaces[iface_name] = HANAFirewallConfInst.ifaces.fetch(iface_name, {}).merge({svc_cidr[0] => svc_cidr[1]})
                        UI.ChangeWidget(Id(:manual_svc), :Value, '')
                        refresh_lists
                    when :help
                        Popup.LongMessageGeometry(_("HANA firewall works on top of SUSE firewall, to help securing your network traffic." +
"Any service that you allow on HANA firewall will override the decision of SUSE firewall.<br/><br/>" +
"Please enter HANA network interface names and choose allowed services for each network interface.<br/>" +
"If you are adding other services, you can find a complete list of service names in \"/etc/services\" file.<br/><br/>" +
"You may also administrate HANA firewall using command \"hana-firewall\"." +
"See \"man 8 hana-firewall\" for more information on HANA firewall administration.<br/><br/>" +
"Please note that the pre-defined HANA services are only for single-tenant HANA installation." +
"If you have a multi-tenant HANA installation, please define HANA application services by calling /etc/hana-firewall.d/create_new_service and then re-visit this module."
), 60, 16)
                    when :cancel
                        return
                end
            end
        end
    end
end
