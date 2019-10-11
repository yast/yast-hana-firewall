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
# Author: Peter Varkoly <varkoly@suse.com>

require 'yast'
require 'ui/dialog'
require 'hanafirewall/hanafirewall_conf'

# In yast2 4.1.3 a reorganization of the YaST systemd library was introduced. When running on an
# older version, just fall back to the old SystemdService module (bsc#1146220).
begin
  require 'yast2/systemd/service'
rescue LoadError
  Yast.import 'SystemdService'
end

#begin
#  require 'yast2/systemd/unit'
#rescue LoadError
#  require 'yast2/systemd_unit'
#end

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
                    Heading(_('Firewall Service-Zone Assignment For HANA')),
                )),
                VBox(
                    # On top there are daemon controls and label showing HANA instance names
                    VSpacing(1.0),
                    HBox(
                        VBox(
                            Left(Frame(_('Global Options'), VBox(
                                Left(CheckBox(Id(:reload), _('Enable and reload firewalld'), false)),
                                Left(InputField(Id(:inst_numbers), _('Instance numbers'), get_inst_numbers.join(' '))),
                            ))),
                            SelectionBox(Id(:avail_svcs), _('Services:')),
                        ),
                        VBox(PushButton(Id(:add_svc), _('→')), PushButton(Id(:del_svc), _('←'))),
                        VBox(
                            Left(ComboBox(Id(:zones), Opt(:notify), _('Zone'), [])),
                            SelectionBox(Id(:selected_svcs), _(''))
                        ),
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
            if !package_present && Popup.YesNo(_('Install HANA-Firewall package?')) && Package.DoInstall(['HANA-Firewall'])
                package_present = true
            end
            if !package_present
                return :finish_dialog
            end

            # Load current service assignment
            @zone_services = get_zone_services

            if @zone_services.empty?
                Popup.Error(_('Firewalld configuration is empty. Please set up firewalld before visiting this program.'))
                return :finish_dialog
            end

            # Put zone names into drop down
            UI.ChangeWidget(Id(:zones), :Items, @zone_services.keys.sort)

            # Pre-select the first zone
            UI.ChangeWidget(Id(:selected_svcs), :Value, @zone_services.keys.sort[0])

            # Load service list
            load_for_selected_zone

            # Begin the event loop
            begin
                event_loop
            ensure
                UI.CloseDialog
            end
            return :finish_dialog
        end

        # Load service list for the currently selected zone name.
        def load_for_selected_zone
            zone_name = UI.QueryWidget(Id(:zones), :Value)
            zone_svcs = @zone_services[zone_name]
            hana_svcs = get_service_names
            selected_svcs = zone_svcs & hana_svcs
            avail_svcs = hana_svcs - selected_svcs

            UI.ChangeWidget(Id(:avail_svcs), :Items, avail_svcs.sort)
            UI.ChangeWidget(Id(:selected_svcs), :Items, selected_svcs.sort)
            UI.RecalcLayout
        end

        def event_loop
            loop do
                case UI.UserInput
                    when :ok
                        set_inst_numbers(UI.QueryWidget(Id(:inst_numbers), :Value).strip.split(/\s+/))
                        regen_svcs
                        ::Y2Firewall::Firewalld.instance.write
                        if UI.QueryWidget(Id(:reload), :Value)
                            restart_service('firewalld')
                        end
                        return
                    when :zones
                        load_for_selected_zone
                    when :add_svc
                        svc = UI.QueryWidget(Id(:avail_svcs), :CurrentItem)
                        zone_name = UI.QueryWidget(Id(:zones), :Value)
                        if svc and zone_name
                            @zone_services[zone_name] += [svc]
                            ::Y2Firewall::Firewalld.instance.zones.find{ |z| z.name == zone_name}.services += [svc]
                            load_for_selected_zone
                        end
                    when :del_svc
                        svc = UI.QueryWidget(Id(:selected_svcs), :CurrentItem)
                        zone_name = UI.QueryWidget(Id(:zones), :Value)
                        if svc and zone_name
                            @zone_services[zone_name] -= [svc]
                            ::Y2Firewall::Firewalld.instance.zones.find{ |z| z.name == zone_name}.services -= [svc]
                            load_for_selected_zone
                        end
                    when :help
                        Popup.LongMessageGeometry(_("HANA firewall is not an independent firewall! It is a utility for firewalld.
The command line tool generates firewalld service definitions, and this graphical tool assigns those services to zones.
You must use firewalld controls (such as firewall-cmd command line) to manipulate the actual firewall setup, such as interface assignment."
), 60, 16)
                    when :cancel
                        return
                end
            end
        end

	private

        def restart_service(name)
            service_api = defined?(Yast2::Systemd::Service) ? Yast2::Systemd::Service : Yast::SystemdService
            service = service_api.find!(name)
	    service.send(:restart)
        end

    end
end
