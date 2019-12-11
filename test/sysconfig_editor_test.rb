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
# Authors: Howard Guo <hguo@suse.com>
# Authors: Peter Varkoly <varkoly@suse.com>

ENV['Y2DIR'] = File.expand_path('../../src', __FILE__)

require 'yast'
require 'yast/rspec'
require 'hanafirewall/sysconfig_editor'

include Yast
include HANAFirewall

sample_conf = '
# this is a comment

ABC123="foo123"
DEF456="bar456"

SEQ_0="a"
SEQ_2="c"

ARY_0="a"
ARY_1="b"
ARY_2="c"
ARY_3="d"
ARY_4="e"
ARY_5="f"
ARY_6="g"

ghi=789

# yadi yadi yada
'

describe SysconfigEditor do
    sysconf = nil
    it 'Parse input file' do
        sysconf = SysconfigEditor.new(sample_conf)
        expect(sysconf.keys.length).to eq(5)
    end

    it 'Get ordinary values' do
        expect(sysconf.get('ABC123')).to eq('foo123')
        expect(sysconf.get('DEF456')).to eq('bar456')
        expect(sysconf.get('ghi')).to eq('789')
        expect(sysconf.get('ARY')).to eq('')
        expect(sysconf.get('ARY_')).to eq('')
    end

    it 'Set ordinary values' do
        expect(sysconf.set('ABC123', 'foo')).to eq(true)
        expect(sysconf.set('DEF456', 'bar')).to eq(true)
        expect(sysconf.set('newkey', 'baz')).to eq(false)

        expect(sysconf.get('ABC123')).to eq('foo')
        expect(sysconf.get('DEF456')).to eq('bar')
        expect(sysconf.get('newkey')).to eq('baz')
    end

    it 'Seek in arrays' do
        expect(sysconf.array_len('does_not_exist')).to eq(0)
        expect(sysconf.array_len('SEQ')).to eq(3)
        expect(sysconf.array_get('SEQ', 0)).to eq('a')
        expect(sysconf.array_get('SEQ', 1)).to eq('')
        expect(sysconf.array_get('SEQ', 2)).to eq('c')
        expect(sysconf.array_len('ARY')).to eq(7)
        expect(sysconf.array_get('ARY', 0)).to eq('a')
        expect(sysconf.array_get('ARY', 1)).to eq('b')
        expect(sysconf.array_get('ARY', 2)).to eq('c')
        expect(sysconf.array_get('ARY', 3)).to eq('d')
        expect(sysconf.array_get('ARY', 6)).to eq('g')
    end

    it 'Set in arrays' do
        expect(sysconf.array_set('ARY', 6, 'gggg')).to eq(true)
        expect(sysconf.array_set('ARY', 9, 'test')).to eq(false)
    end

    it 'Resize arrays' do
        # Not resizing
        sysconf.array_resize('SEQ', 3)
        expect(sysconf.array_len('SEQ')).to eq(3)
        expect(sysconf.array_get('SEQ', 0)).to eq('a')
        expect(sysconf.array_get('SEQ', 1)).to eq('')
        expect(sysconf.array_get('SEQ', 2)).to eq('c')
        expect(sysconf.array_get('SEQ', 3)).to eq('')

        # Enlarge
        sysconf.array_resize('SEQ', 5)
        expect(sysconf.array_len('SEQ')).to eq(5)
        expect(sysconf.array_get('SEQ', 0)).to eq('a')
        expect(sysconf.array_get('SEQ', 1)).to eq('')
        expect(sysconf.array_get('SEQ', 2)).to eq('c')
        expect(sysconf.array_get('SEQ', 3)).to eq('')
        expect(sysconf.array_get('SEQ', 4)).to eq('')
        expect(sysconf.array_get('SEQ', 5)).to eq('')

        # Shrink
        sysconf.array_resize('SEQ', 2)
        expect(sysconf.array_len('SEQ')).to eq(1)
        expect(sysconf.array_get('SEQ', 0)).to eq('a')
        expect(sysconf.array_get('SEQ', 1)).to eq('')
        expect(sysconf.array_get('SEQ', 2)).to eq('')

        # Erase
        sysconf.array_resize('SEQ', 0)
        expect(sysconf.array_len('SEQ')).to eq(0)
        expect(sysconf.array_get('SEQ', 0)).to eq('')

        # Create new array
        sysconf.array_resize('new_array', 3)
        expect(sysconf.array_len('new_array')).to eq(3)
        expect(sysconf.array_get('new_array', 0)).to eq('')
        expect(sysconf.array_get('new_array', 1)).to eq('')
        expect(sysconf.array_get('new_array', 2)).to eq('')
    end

    it 'Convert back to text' do
        expect(sysconf.to_text).to eq ('
# this is a comment

ABC123="foo"
DEF456="bar"


ARY_0="a"
ARY_1="b"
ARY_2="c"
ARY_3="d"
ARY_4="e"
ARY_5="f"
ARY_6="gggg"

ghi=789

# yadi yadi yada
newkey="baz"
ARY_9="test"
new_array_0=""
new_array_1=""
new_array_2=""
')
    end
end
