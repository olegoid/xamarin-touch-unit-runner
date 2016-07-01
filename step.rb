require 'optparse'
require 'fileutils'
require 'tmpdir'

require_relative 'xamarin-builder/builder'

# -----------------------
# --- Constants
# -----------------------

TOUCH_SERVER_PROJ = "./Touch.Unit/Touch.Server/Touch.Server.csproj"
TOUCH_SERVER = "./Touch.Unit/Touch.Server/bin/Debug/Touch.Server.exe"

# -----------------------
# --- Functions
# -----------------------

def error_with_message(message)
  puts "\e[31m#{message}\e[0m"
end

# -----------------------
# --- Main
# -----------------------

#
# Parse options
options = {
  solution: nil,
  configuration: nil,
  platform: nil
}

parser = OptionParser.new do |opts|
  opts.banner = 'Usage: step.rb [options]'
  opts.on('-s', '--solution path', 'Solution') { |s| options[:solution] = s unless s.to_s == '' }
  opts.on('-c', '--configuration config', 'Configuration') { |c| options[:configuration] = c unless c.to_s == '' }
  opts.on('-l', '--platform platform', 'Platform') { |l| options[:platform] = l unless l.to_s == '' }
  opts.on('-h', '--help', 'Displays Help') do
    exit
  end
end
parser.parse!

#
# Print options
puts
puts '========== Configs =========='
puts " * solution: #{options[:solution]}"
puts " * configuration: #{options[:configuration]}"
puts " * platform: #{options[:platform]}"

#
# Validate options
fail_with_message("No solution file found at path: #{options[:solution]}") unless options[:solution] && File.exist?(options[:solution])
fail_with_message('No configuration environment found') unless options[:configuration]

#
# Main
builder = Builder.new(options[:solution], options[:configuration], options[:platform], nil)
begin
  # Build Touch.Unit server
  puts `xbuild #{TOUCH_SERVER_PROJ}`

  # The solution has to be built before runing the Touch.Unit tests
  builder.build_solution

  output = builder.generated_files

  error_with_message('no output generated') if output.nil? || output.empty?
  app_file = nil

  output.each do |_, project_output|
    app_file = project_output[:app] if project_output[:api] == Api::IOS
  end

  error_with_message('*.app required to run Touch.Unit tests') unless app_file

  # run app on simulator with mono debugger attached
  `mono --debug #{TOUCH_SERVER} --launchsim #{app_file} -autoexit -logfile=test.log`

  result = Hash.new

  # check test logs
  if File.exist?('test.log')
  	File.open('test.log', "r") do |f|
  	  f.each_line do |line|
        puts line
        if line.start_with?('Tests run')
        	line.gsub (/[a-zA-z]*: [0-9]*/) { |s|
        	  s.delete!(' ')
        	  test_result = s.split(/:/)
        	  result[test_result.first] = test_result.last
        	}
        end
      end
    end
  else
  	error_with_message('Cant find test logs file')
  end

  # show results
  raise 'Test failed' if result['Failed'] != '0'
rescue => ex
  error_with_message(ex.inspect.to_s)
  error_with_message('--- Stack trace: ---')
  error_with_message(ex.backtrace.to_s)
  exit(1)
end