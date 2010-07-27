###############################################################################
# Copyright 2010 SugarCRM, Inc.
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
###############################################################################

###############################################################################
# Needed Ruby libs:
###############################################################################
require 'MeterMaid'
require 'getoptlong'

###############################################################################
# Global Data:
###############################################################################
   $VERSION = 1.0

###############################################################################
# PrintHelp -- Function
#     This function prints the needed --help message.
#
# Input:
#     None.
#
# Output:
#     Always returns 0
#
###############################################################################
def PrintHelp()
   msg = <<HLP
#{$0} Version: #{$VERSION}
MeterMaid.rb Version: #{MeterMaid::METER_MAID_VERSION}\n

Usage:
   #{$0} --inputfile="mytest.xml" --outputfile="new-jmeter-test.jmx"

Required Flags:
   --inputfile: This is the input simple MeterMaid XML file.

   --outputfile: This is the newly created Jmeter test.

Optional Flags:
   --help: Prints this message and exits.

HLP

   print "#{msg}\n"

   return 0
end

###############################################################################
# Main -- Function
#     This is a C like main function to make for easier debugging and reading.
#
# Input:
#     None.
#
# Output:
#     Always returns 0
#
###############################################################################
def Main()
   opts = nil
   input_file = nil
   output_file = nil
   maid = nil

   begin
      opts = GetoptLong.new(
               [ '--help', '-h', GetoptLong::NO_ARGUMENT ],
               [ '--inputfile', '-i', GetoptLong::REQUIRED_ARGUMENT ],
               [ '--outputfile', '-o', GetoptLong::REQUIRED_ARGUMENT ]
            )

      opts.quiet = true
      opts.each do |opt, arg|
         case opt
            when "--help"
               PrintHelp()
               exit(0)
            when "--inputfile"
               input_file = arg
            when "--outputfile"
               output_file = arg
         end
      end

   rescue Exception => e
      print "(!)Error: #{e.message}\n"
      exit(-1)
   end

   if ( (output_file == nil) || (input_file == nil) )
      print "(!)Error: Missing needed param!\n"
      PrintHelp()
      exit(-1)
   end

   if (!File.exist?(input_file))
      print "(!)Error: Failed to file needed --inputfile: \"#{input_file}\"!\n"
      exit(-1)
   end

   print "(*)Starting jmeter test generation...\n"
   maid = MeterMaid.new({
         'testfile' => "#{input_file}",
         'outputfile' => "#{output_file}"
         })

   print "(*)Done.\n"

   return 0
end

###############################################################################
# Start executing code here --->
###############################################################################
   Main()
   exit(0)

