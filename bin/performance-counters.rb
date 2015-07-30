#! /usr/bin/env ruby
#
#   metrics.rb
#
# DESCRIPTION:
#
# OUTPUT:
#   metric data
#
# PLATFORMS:
#   Windows
#
# DEPENDENCIES:
#   gem: sensu-plugin
#
# USAGE:
# A configuration file is required. It should be a YAML with this structure:
#   ---
#   PERFORMANCE COUNTER:
#     scheme: RELATIVE.SCHEME
#     min: VALUE
#     max: VALUE
#   ...
#
# Just the performance counter is mandatory. The rest is optional and his meaning is:
# - scheme: relative scheme to be used. It will use the performance counter name if empty.
# - min: checks the value to be higher than this or fails.
# - max: checks the value to be lower than this or fails.
#
# NOTES:
#  Tested on Windows 2012RC2.
#
# LICENSE:
#   Miguel Angel Garcia <miguelangel.garcia@gmail.com>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'sensu-plugin/metric/cli'
require 'socket'
require 'yaml'
require 'csv'

#
# Generic Metrics
#
class GenericMetric < Sensu::Plugin::Metric::CLI::Graphite
  option :scheme,
         description: 'Global scheme, text to prepend to .$relative_scheme',
         long: '--scheme SCHEME',
         default: "#{Socket.gethostname}"

  option :file,
         short: '-f file',
         default: 'metrics.yaml'

  def check_min(data)
    return true unless data.include? 'min'
    min = data['min']
    return true unless v.to_f < min.to_f
    puts "CHECK ERROR: Value #{v} is higher than #{min} for key #{key}"
    false
  end

  def check_max(data)
    return true unless data.include? 'max'
    max = data['max']
    return true unless v.to_f > max.to_f
    puts "CHECK ERROR: Value #{v} is lower than #{max} for key \\#{key}"
    false
  end

  def run
    metrics = YAML.load_file(config[:file])

    counters = metrics.keys
    is_ok = true

    flatten = counters.map { |s| "\"#{s}\"" }.join(' ')
    timestamp = Time.now.utc.to_i
    IO.popen("typeperf -sc 1 #{flatten} ") do |io|
      CSV.parse(io.read, headers: true) do |row|
        row.shift
        row.each do |k, v|
          next unless v && k
          break if row.to_s.start_with? 'Exiting'

          key = k.split('\\', 4)[3]
          data = metrics.fetch("\\#{key}", nil)
          next unless data

          relative_scheme = data.fetch('scheme', nil)
          relative_scheme ||= key.tr('{}()\- .', '_').tr('\\', '.')

          value = format('%.2f', v.to_f)
          name = [config[:scheme], relative_scheme].join('.')

          output name, value, timestamp

          # if min and max keys not included then skip the rest
          next unless data.include?('min') || data.include?('max')

          min_ok = check_min(data)
          max_ok = check_max(data)
          # if min or max are both true then dont set is_ok = false
          is_ok = false unless min_ok && max_ok
        end
      end
    end
    if is_ok
      ok
    else
      critical
    end
  end
end
