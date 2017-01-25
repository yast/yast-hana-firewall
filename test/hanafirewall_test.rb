#!/usr/bin/env rspec
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
#
# Authors: Howard Guo <hguo@suse.com>

ENV['Y2DIR'] = File.expand_path('../../src', __FILE__)

require 'yast'
require 'yast/rspec'
require 'hanafirewall/hanafirewall_conf'

include Yast
include HANAFirewall

sample_conf = '
# yadi yadi yada
HANA_SYSTEMS="TTT00 UUU01"
OPEN_ALL_SSH="yes"
INTERFACE_0="eth0"

INTERFACE_0_SERVICES="smtp ssh:10.0.0.0/24 ntp:10.10.10.1 HANA_HTTP_CLIENT_ACCESS"
INTERFACE_1="eth1"
INTERFACE_1_SERVICES="HANA_SYSTEM_REPLICATION HANA_DISTRIBUTED_SYSTEMS HANA_SAP_SUPPORT"
# These interfaces do not carry any service and will not appear in result text
INTERFACE_2="eth2"
INTERFACE_2_SERVICES=""
INTERFACE_3="eth3"
'

describe ServiceDefinitions do
    it 'Read network service definitions' do
        expect(ServiceDefinitionsInst.interpret_svc_definition('
            ## Name: HANA Database Client Access
            yadi yadi yada

            ICMP="1"
            TCP="1__INST_NUM__2 34"
            UDP=9__INST_NUM__0 12
        ')).to eq([
            [PortRegexMatcher.new(/^1[0-9]{2}2$/), PortRegexMatcher.new(/^34$/)],
            [PortRegexMatcher.new(/^9[0-9]{2}0$/), PortRegexMatcher.new(/^12$/)],
        ])
    end

    it 'Read standard service definitions' do
        std_svcs = ServiceDefinitionsInst.std_svcs
        expect(std_svcs.length).to be > 500
        expect(std_svcs['tcpmux']).to eq({
            :tcp => [PortRegexMatcher.new(/^1$/)],
            :udp => [PortRegexMatcher.new(/^1$/)]
        })
        expect(std_svcs['ident']).to eq({
            :tcp => [PortRegexMatcher.new(/^113$/)],
            :udp => []
        })
        expect(std_svcs['gist']).to eq({
            :tcp => [],
            :udp => [PortRegexMatcher.new(/^270$/)]
        })
    end

    it 'Read HANA service definitions' do
        expect(ServiceDefinitionsInst.hana_service_names.length).to be > 9
        hana_svcs = ServiceDefinitionsInst.hana_svcs
        expect(hana_svcs.length).to eq ServiceDefinitionsInst.hana_service_names.length
        expect(hana_svcs['HANA_DATABASE_CLIENT']).to eq({
            :tcp => [PortRegexMatcher.new(/^3[0-9]{2}15$/), PortRegexMatcher.new(/^3[0-9]{2}17$/)],
            :udp => []
        })
        expect(hana_svcs['NFS_SERVER']).to eq({
            :tcp => [
                PortRangeMatcher.new(10050, 10054),
                PortRangeMatcher.new(10050, 10054),
                PortRegexMatcher.new(/^111$/),
                PortRegexMatcher.new(/^111$/),
                PortRegexMatcher.new(/^2049$/),
                PortRegexMatcher.new(/^2049$/),
            ],
            :udp => [
                PortRangeMatcher.new(10050, 10054),
                PortRangeMatcher.new(10050, 10054),
                PortRegexMatcher.new(/^111$/),
                PortRegexMatcher.new(/^111$/),
                PortRegexMatcher.new(/^2049$/),
                PortRegexMatcher.new(/^2049$/),
            ],
        })
    end

    it 'Find corresponding service for a port' do
        expect(ServiceDefinitionsInst.find_port(99999, :udp)).to eq(nil)
        expect(ServiceDefinitionsInst.find_port(22, :tcp)).to eq([:std, 'ssh'])
        expect(ServiceDefinitionsInst.find_port(25, :tcp)).to eq([:std, 'smtp'])
        expect(ServiceDefinitionsInst.find_port(53, :udp)).to eq([:std, 'domain'])
        # HANA-defined services
        expect(ServiceDefinitionsInst.find_port(30015, :tcp)).to eq([:hana, 'HANA_DATABASE_CLIENT'])
        expect(ServiceDefinitionsInst.find_port(30115, :tcp)).to eq([:hana, 'HANA_DATABASE_CLIENT'])
        expect(ServiceDefinitionsInst.find_port(30017, :tcp)).to eq([:hana, 'HANA_DATABASE_CLIENT'])
        expect(ServiceDefinitionsInst.find_port(30117, :tcp)).to eq([:hana, 'HANA_DATABASE_CLIENT'])
        expect(ServiceDefinitionsInst.find_port(10050, :tcp)).to eq([:hana, 'NFS_SERVER'])
        expect(ServiceDefinitionsInst.find_port(10051, :tcp)).to eq([:hana, 'NFS_SERVER'])
        expect(ServiceDefinitionsInst.find_port(10054, :tcp)).to eq([:hana, 'NFS_SERVER'])
    end
end

describe HANAFirewallConf do
    it 'Read configuration file' do
        HANAFirewallConfInst.load(sample_conf)
        expect(HANAFirewallConfInst.hana_sys).to eq(['TTT00', 'UUU01'])
        expect(HANAFirewallConfInst.open_ssh).to eq(true)
        expect(HANAFirewallConfInst.ifaces).to eq({
            "eth0"=>{
                "smtp"=>"0.0.0.0/0", "ssh"=>"10.0.0.0/24", "ntp"=>"10.10.10.1",
                "HANA_HTTP_CLIENT_ACCESS"=>"0.0.0.0/0"
            },
            "eth1"=>{
                "HANA_SYSTEM_REPLICATION"=>"0.0.0.0/0",
                "HANA_DISTRIBUTED_SYSTEMS"=>"0.0.0.0/0",
                "HANA_SAP_SUPPORT"=>"0.0.0.0/0"
            },
            "eth2"=>{}, "eth3"=>{}
        })
    end

    it 'Generate configuration file' do
        expect(HANAFirewallConfInst.to_text).to eq('
# yadi yadi yada
HANA_SYSTEMS="TTT00 UUU01"
OPEN_ALL_SSH="yes"

# These interfaces do not carry any service and will not appear in result text
INTERFACE_0="eth0"
INTERFACE_0_SERVICES="smtp ssh:10.0.0.0/24 ntp:10.10.10.1 HANA_HTTP_CLIENT_ACCESS"
INTERFACE_1="eth1"
INTERFACE_1_SERVICES="HANA_SYSTEM_REPLICATION HANA_DISTRIBUTED_SYSTEMS HANA_SAP_SUPPORT"
')
    end

    it 'Manipulate firewall state' do
        expect(HANAFirewallConfInst.state).to eq false
        ok, _ = HANAFirewallConfInst.set_state(true)
        # firewall is not installed, and the test is not running as root
        expect(ok).to eq false
    end

    it 'Retrieve running services' do
        expect(HANAFirewallConfInst.running_hana_services).not_to eq(nil)
    end

    it 'Generate configuration automatically' do
        new_conf = HANAFirewallConfInst.gen_config
        # Make sure that original configuration is still present
        expect(new_conf[:hana_sys]).to eq(["TTT00", "UUU01"])
        expect(new_conf[:open_ssh]).to eq(true)
        expect(new_conf[:ifaces]['eth0']).to eq({"smtp"=>"0.0.0.0/0", "ssh"=>"10.0.0.0/24", "ntp"=>"10.10.10.1", "HANA_HTTP_CLIENT_ACCESS"=>"0.0.0.0/0"})
        expect(new_conf[:ifaces]['eth1']).to eq({"HANA_SYSTEM_REPLICATION"=>"0.0.0.0/0", "HANA_DISTRIBUTED_SYSTEMS"=>"0.0.0.0/0", "HANA_SAP_SUPPORT"=>"0.0.0.0/0"})
    end
end
