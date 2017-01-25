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

Yast.import 'Service'

module HANAFirewall
    # A smart sysconfig file editor that not only can handle key-value but also arrays.
    # Array is identified by a key with _{number} suffix.
    # Specially tailored for HANA firewall.
    class SysconfigEditor
        def initialize(text)
            @lines = text.b.split("\n")
        end

        # Return all keys.
        # If a key represents an array, then the key (rather than every index of it) will be returned.
        def keys
            ret = []
            scan(/.*/) { | key, idx, val|
                if idx == :nil || idx == 0
                    ret << key
                end
                [:continue]
            }
            return ret
        end

        # Return value, or empty string if the key does not exist.
        # Calling this function on an array key will return an empty string.
        def get(key)
            ret = ''
            scan(/^#{key}$/) { |_, idx, val|
                if idx == :nil
                    ret = val
                    [:stop]
                else
                    [:continue]
                end
            }
            return ret
        end

        # Set value or create the key if it does not exist. Return true only if the key was found.
        def set(key, val)
            found = false
            scan(/^#{key}$/) { |_, _, _|
                found = true
                [:set, val]
            }
            if !found
                @lines << "#{key}=\"#{val}\""
            end
            return found
        end

        # Return length of array represented by the key.
        # Return 0 if the key does not exist.
        def array_len(key)
            # By contract an array key must use an underscore before index number
            max_idx = -1
            scan(/^#{key}_*$/) { |_, idx, _|
                if idx != nil && idx > max_idx
                    max_idx = idx
                end
                [:continue]
            }
            return max_idx + 1
        end

        # Return array value that corresponds to the key and index.
        # Return empty string if the key does not exist, or the index does not exist/out of bound.
        def array_get(key, index)
            ret = ''
            scan(/^#{key}_*$/) { |_, idx, val|
                if idx == index
                    ret = val
                    [:stop]
                else
                    [:continue]
                end
            }
            return ret
        end

        # Set array value or create the key/index if it does not exist. Return true only if index was found.
        def array_set(key, index, val)
            found = false
            scan(/^#{key}_*$/) { |_, idx, _|
                if idx == index
                    found = true
                    [:set, val]
                else
                    [:continue]
                end
            }
            if !found
                @lines << "#{key}_#{index}=\"#{val}\""
            end
            return found
        end

        # Shrikn or enlarge the array to match the specified length.
        # If specified length is 0, the entire array is erased.
        def array_resize(key, new_len)
            seen_idx = -1
            scan(/^#{key}_*$/) { |_, idx, val|
                if idx == nil
                    [:continue]
                elsif idx >= new_len
                    if idx - 1 > seen_idx
                        seen_idx = idx - 1
                    end
                    # Remove excesive indexes
                    [:delete_continue]
                else
                    seen_idx = idx
                end
            }
            # Introduce extra indexes
            (seen_idx+1..new_len-1).each{ |idx|
                @lines << "#{key}_#{idx}=\"\""
            }
        end

        # Produce sysconfig file text, including all the modifications that have been done.
        def to_text
            return @lines.join("\n") + "\n"
        end

        # Scan all lines looking for keys matching the specified regex.
        # Call code block with three parameters:
        # - key without index number
        # - index number, :nil if not an array
        # - value
        # Code block is expected to return an array:
        # [:stop] - stop scanning and end
        # [:continue] - continue scanning
        # [:delete_stop] - delete the key (or array element) and stop
        # [:delete_continue] - delete the key (or array element) and continue
        # [:set, $new_value] - update the value (or array element value) and stop
        def scan(key_regex, &block)
            to_delete_idx = []
            (0..@lines.length-1).each { |idx|
                line = @lines[idx].strip
                param = nil
                # Test against array key
                array_kiv = /^([A-Za-z0-9_]+)_([0-9])+="?([^"]*)"?$/.match(line)
                if array_kiv != nil
                    param = [array_kiv[1], array_kiv[2].to_i, array_kiv[3]]
                else
                    # Test against ordinary key
                    kv = /^([A-Za-z0-9_]+)="?([^"]*)"?$/.match(line)
                    if kv != nil
                        param = [kv[1], :nil, kv[2]]
                    end
                end
                if param != nil && key_regex.match(param[0])
                    # Invoke code block and act upon the result
                    result = block.call(*param)
                    case result[0]
                        when :stop
                            break
                        when :continue
                            next
                        when :delete_stop
                            to_delete_idx << idx
                            break
                        when :delete_continue
                            to_delete_idx << idx
                            next
                        when :set
                            if array_kiv == nil
                                @lines[idx] = "#{param[0]}=\"#{result[1]}\""
                            else
                                @lines[idx] = "#{param[0]}_#{param[1]}=\"#{result[1]}\""
                            end
                            break
                    end
                end
            }
            to_delete_idx.reverse.each {|idx|
                @lines.slice!(idx)
            }
        end

    end
end
