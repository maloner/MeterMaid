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
# Needed ruby libs:
###############################################################################
require 'rubygems'
require 'libxml'
require 'date'

###############################################################################
# Global Data:
###############################################################################
   METER_MAID_VERSION = 1.0

###############################################################################
# MeterMaid: Class
#     This class reads a simplified jmeter XML file and generates a valid
#     jmeter jmx file.
#
# Input:
#     params: This is a hash of params to be passed to the class constructor.
#
# Valid params: 
#     'testfile': This is the simplified XML file to be used to generate a 
#        valid jmeter file.
#
#     'outputfile': This is what the output jmeter file will be called.
#
# Output:
#     None.
#
###############################################################################
class MeterMaid

   def initialize(params = {})
      @doc = nil
      @outputfile = nil
      $ThreadGroupNum = 0

      if (!params.key?('testfile'))
         msg = "Error: Failed to find needed test file!"
         raise msg
      elsif (!params.key?('outputfile'))
         msg = "Error: Failed to find needed output file!"
         raise msg
      end

      @doc = ParseXML(params['testfile'])
      if (@doc == nil)
         raise "Failed when parsing XML file!"
      end

      tmp = GetDataFromTest(@doc)
      tmp.each do |key, value|
         if (key =~ /tests/i)
            next
         end
      end

      GenerateJXM(params['outputfile'], tmp)

   end

###############################################################################
# SafeStr -- Method
#     This method escapes strings to make them XML safe.
#
# Input:
#     str: The string to escape.
#
# Output:
#     returns an xml safe string.
#
###############################################################################
   def SafeStr(str)
      lookup = {
         '<' => '&lt;',
         '>' => '&gt;',
         '&' => '&amp;'
      }

      lookup.each do |k, v|
         str = str.gsub("#{k}", "#{v}")
      end

      return str
   end

###############################################################################
# GetDataFromTest -- Method
#     This function processes the XML dom spliting all the elements into
#     hashes and arrays.
#
# Input:
#     None.
#
# Output:
#     Returns a hash of hashes and arrarys.
#
###############################################################################
   def GetDataFromTest(root_doc)
      data = {
         'stack' => [],
         'csv_stack' => [],
         'testinfo.numthreads' => 1
      }

      root_doc.root.each do |node|
         if (node.name == 'text')
            next
         end

         case (node.name)
            when "timer"
               next if (!node.children?)
               tmp = ProcessTimer(node)
               data['stack'].push( {'timer' => tmp} )
            when "loop"
               next if (!node.children?)
               
               loop_kids = node.children()
               data['stack'].push( {'loop' => loop_kids} )
            when "controller"
               next if (!node.children?)

               ctrl_hash = ProcessControllerElement(node) 
               data['stack'].push( {'controller' => ctrl_hash} )
            when "testinfo"
               kids = node.children()
               kids.each do |kid|
                  if (kid.name == "text")
                     next
                  end

                  data["testinfo." + "#{kid.name}"] = "#{SafeStr(kid.content)}"
               end
            when "http"
               tmp = ProcessHttpElement(node)
               data['stack'].push( {'http' => tmp} )
            when "csv"
               tmp = ProcessCSVElement(node)
               data['csv_stack'].push(tmp)
            when "script"
               next if (!node.children?)
               
               script_hash = Hash.new()
               script_kids = node.children()
               script_kids.each do |script|
                  next if (script.name =~ /text/i)
                  script_hash["#{script.name}"] = "#{SafeStr(script.content)}"
                  script_hash['line_number'] = "#{node.line_num}"
                  tmp = ProcessScripts(script_hash)
                  tmp = GetDataFromTest(tmp)
                  data['stack'].concat(tmp['stack'])
                  data['csv_stack'].concat(tmp['csv_stack'])
               end
         end
      end

      return data
   end
   private :GetDataFromTest

###############################################################################
# ProcessTimer -- Method
#     This method creates a hash for a timer element.
#
# Input:
#     timer: This is a timer node from the XML dom.
#
# Output:
#     returns a hash with all the needed values for a jmeter timer, or 
#     nil on error
#
###############################################################################
   def ProcessTimer(timer)
      error = 0
      hash = {
         'name' => 'Timer: Undefined Name',
         'delay' => nil,
         'range' => nil
      }

      kids = timer.children()
      kids.each do |kid|
         next if (kid.name =~ /text/i)
         hash["#{kid.name}"] = SafeStr(kid.content)
      end
 
      hash.each do |k, v|
         if (hash[k] == nil)
            print "Found a nil value for a timer element for key: #{k}!\n"
            print "--)Line: #{kid.line_num}!\n"
            error = -1
         end
      end

      hash = nil if (error != 0)

      return hash

   end
   private :ProcessTimer

###############################################################################
# GenerateTimer -- Method
#     Thsi method creates jmeter xml from a Timer hash from ProcessTimer.
#
# Input:
#     timer: This is the timer hash.
#
# Output:
#     rerurns a string of jmeter xml for a timer.
#
###############################################################################
   def GenerateTimer(timer)
      timer_str = <<XML
    <GaussianRandomTimer guiclass="GaussianRandomTimerGui" 
      testclass="GaussianRandomTimer" 
      testname="Gaussian Timer: #{timer['name']}" 
      enabled="true">
          <stringProp name="ConstantTimer.delay">#{timer['delay']}</stringProp>
          <stringProp name="RandomTimer.range">#{timer['range']}</stringProp>
        </GaussianRandomTimer>
        <hashTree/>
XML

      return timer_str
   end
   private :GenerateTimer

###############################################################################
# ProcessControllerElement -- Method
#     This method processes a Controller element from the XML test.
#
# Input:
#     node: This is a test node from the XML dom.
#
# Output:
#     Returns a hash containing all the data from the controller element.
#
###############################################################################
   def ProcessControllerElement(node)
      ctrl_kids = node.children()
      ctrl_hash = {
         'line_number' => "#{node.line_num}",
         'stack' => [],
         'csv_stack' => []
      }
      ctrl_kids.each do |ctrl|
         next if (ctrl.name =~ /text/)

         if (ctrl.name =~ /http/i)
            tmp = ProcessHttpElement(ctrl)
            ctrl_hash['stack'].push( {'http' => tmp} )
         elsif(ctrl.name =~ /loop/i)
            ctrl_hash['stack'].push( {'loop' => ctrl} )
         elsif(ctrl.name =~/controller/i)
            tmp = ProcessControllerElement(ctrl)
            ctrl_hash['stack'].push( {'controller' => tmp} )
         elsif(ctrl.name =~ /script/i)
            next if (!ctrl.children?)
               
            script_hash = Hash.new()
            script_kids = ctrl.children()
            script_kids.each do |script|
               next if (script.name =~ /text/i)
               script_hash["#{script.name}"] = "#{SafeStr(script.content)}"
               script_hash['line_number'] = "#{node.line_num}"
               tmp = ProcessScripts(script_hash)
               tmp = GetDataFromTest(tmp)
               ctrl_hash['stack'].concat(tmp['stack'])
               ctrl_hash['csv_stack'].concat(tmp['csv_stack'])
            end

         else
            ctrl_hash["#{ctrl.name}"] = "#{SafeStr(ctrl.content)}"
         end
      end

      return ctrl_hash
   end
   private :ProcessControllerElement


###############################################################################
# ProcessScripts -- Method
#     This method processes the Script elements.
#
# Input:
#     script: This is a hash created by GetDataFromTest().
#
# Output:
#     returns the root_doc from the XML Dom on success, or nil on error.
#
###############################################################################
   def ProcessScripts(script)
      root_doc = nil   

      return nil if (!script.key?('file'))

      if (!File.exist?(script['file']))
         print "Error: Script file doesn't exists: \"#{script['file']}\"!\n"
         print "Line Number: #{script['line_number']}\n"
         return nil
      end

      root_doc = ParseXML(script['file'])

      return root_doc 
   end

###############################################################################
# GenerateCSVData -- Method
#     This method generates JMeter CSV tests.
#
# Input:
#     csv_hash: This is a hash from ProcessCSVElement.
#
# Output: JMeter XML code.
#
###############################################################################
   def GenerateCSVData(csv_hash)
      csv_thread_group = 0
      csv_xml = ""
      repeat = ""
      new_tg = ""

      csv_xml = <<XML
    <CSVDataSet guiclass="TestBeanGUI" testclass="CSVDataSet" 
      testname="CSV Data Set Config: #{csv_hash['name']}" enabled="true">
      <stringProp name="delimiter">,</stringProp>
      <boolProp name="recycle">true</boolProp>
      <stringProp name="filename">#{csv_hash['filename']}</stringProp>
      <stringProp name="variableNames">#{csv_hash['varnames']}</stringProp>
      </CSVDataSet>
      <hashTree/>
XML

      thread_group = <<XML
    <ThreadGroup guiclass="ThreadGroupGui" testclass="ThreadGroup" 
      testname="Thread Group: #{csv_hash['name']}: #{csv_thread_group}" 
      enabled="true">
      <boolProp name="ThreadGroup.scheduler">false</boolProp>
      <stringProp name="ThreadGroup.num_threads">1</stringProp>
      <stringProp name="ThreadGroup.duration"></stringProp>
      <stringProp name="ThreadGroup.delay"></stringProp>
      <longProp name="ThreadGroup.start_time">#{Time.now().to_i}</longProp>
      <stringProp name="ThreadGroup.on_sample_error">continue</stringProp>
      <stringProp name="ThreadGroup.ramp_time">1</stringProp>
      <elementProp name="ThreadGroup.main_controller" 
        elementType="LoopController" guiclass="LoopControlPanel" 
        testclass="LoopController" testname="Loop Controller" enabled="true">
        <stringProp name="LoopController.loops">1</stringProp>
        <boolProp name="LoopController.continue_forever">false</boolProp>
      </elementProp>
      <longProp name="ThreadGroup.end_time">#{Time.now().to_i}</longProp>
    </ThreadGroup>
   <hashTree> <!-- start thread group's hash tree -->
   <CookieManager guiclass="CookiePanel" testclass="CookieManager" 
      testname="HTTP Cookie Manager" enabled="true">
        <boolProp name="CookieManager.clearEachIteration">false</boolProp>
        <collectionProp name="CookieManager.cookies"/>
    </CookieManager>
    <hashTree/> <!-- empty cookies hash tree -->
XML

      csv_hash['stack'].each do |csv_data|
         if (csv_data.key?("loop"))
            new_tg = thread_group
            tmp = GenerateLoop(csv_data['loop'])
            new_tg << tmp
         elsif (csv_data.key?("controller"))
            new_tg = thread_group
            tmp = GenerateController(csv_data['controller'])
            new_tg << tmp
         elsif (csv_data.key?("http"))
            new_tg = thread_group
            tmp = GenerateHttp(csv_data['http'])
            new_tg << tmp
         elsif (csv_data.key?('repeat'))
            line_count = 0
            fd = File.open(csv_hash['filename'], "r")
            lines = fd.readlines()
            fd.close()

            # really shouldn't have to do this, but it makes for a good
            # safe check.
            lines.each do | line |
               line = line.chomp()
               next if (line.empty?)
               line_count += 1
            end

            for i in 1..line_count do
               csv_data['repeat'].each do |item|
                  item.each do |k, v|
                     repeat << thread_group
                     repeat << v
                     repeat << "    </hashTree> <!-- end repeat thread group"+
                        ": #{i} -->\n"
                  end
               end
            end

            csv_xml << repeat
         end

         if (!new_tg.empty?)
            new_tg << "    </hashTree> <!-- end thread group -->\n"
         end

         csv_xml << new_tg
      end

      return csv_xml
   end

###############################################################################
# GenerateController -- Method
#     This method generates a jmeter ThroughputController.
#
# Input:
#     ctrl: This is the controller XML node from the XML dom. 
#
# Output:
#     returns a string of the needed jmeter xml.
#
###############################################################################
   def GenerateController(ctrl)
      ctrl_count = 0
      new_ctrl = ""
      percent = 0
      precentI = 0

      if (!ctrl.key?('name'))
         ctrl['name'] = "My Controller: #{ctrl_count}"
         print "Warning: Failed to find name for controller.  XML line"+
            " number: #{ctrl['line_number']}.\n"
      end

      if (!ctrl.key?('precent'))
         print "Warning: Faild to find percent for controller. XML line"+
            " number: #{ctrl['line_number']}.\n"
         precent = 15.0
         precent = precent.to_f()
      else
         precent = ctrl['precent']
         precent = precent.to_f()
      end

      precentI = precent.to_i()

      new_ctrl = <<XML
    <GenericController guiclass="LogicControllerGui" 
      testclass="GenericController" 
      testname="Simple Controller: #{ctrl_count}" 
      enabled="true"/>
    <hashTree> <!-- start GenericController hashTree -->
    <ThroughputController guiclass="ThroughputControllerGui" 
      testclass="ThroughputController" 
      testname="Throughput Controller: #{ctrl_count}" enabled="true">
      <FloatProperty>
        <value>#{precent}</value>
        <savedValue>0.0</savedValue>
        <name>ThroughputController.percentThroughput</name>
      </FloatProperty>
      <boolProp name="ThroughputController.perThread">true</boolProp>
      <intProp name="ThroughputController.style">1</intProp>
      <intProp name="ThroughputController.maxThroughput">1</intProp>
    </ThroughputController>
    <hashTree> <!-- start ThroughputController hashTree -->
XML

      ctrl['stack'].each do |item|
         if (item.key?('http'))
            test_str = GenerateHttp(item['http'])
            if (test_str != nil)
               new_ctrl << test_str
            end
         elsif (item.key?('loop'))
            loop_str = GenerateLoop(item['loop'])
            if (loop_str != nil)
               new_ctrl << loop_str
            end
         elsif (item.key?('controller'))
            controller_str = GenerateController(item['controller'])
            if (controller_str != nil)
               new_ctrl << controller_str
            end
         end
      end

      new_ctrl << "    </hashTree> <!-- end ThroughputController hashTree"+
         " -->\n    </hashTree> <!-- end GenericController hashTree -->\n"

      return new_ctrl
   end
   private :GenerateController


###############################################################################
# Not finished yet....  Work in progress...
###############################################################################
   def GenericNodeProcess(node)
      data = []

      return nil if (!node.children?)

      node.each do |kid|
         case (kid.name)
            when "text"
               next
            when "http"
               tmp = ProcessHttpElement(kid)
               tmp = GenerateHttp(tmp)
               data.push( {'http' => tmp} )
            when "controller"
               tmp = GenerateController(kid)
               data.push( {'controller' => tmp} )
            when "loop"
               tmp = GenerateLoop(kid)
               data.push( {'loop' => tmp} )
         end
      end   

      return data
   end
   private :GenericNodeProcess

###############################################################################
# ProcessCSVElement -- Method
#     This method processes a csv element from the XML test file and
#     generates tests using the csv file data.
#
# Input:
#     node: This is the csv node from the XML dom.
#
# Output:
#     Returns nil on error, else an array of test hashes on success.
#
###############################################################################
   def ProcessCSVElement(node)
      csv_hash = {
         'stack' => []
      }
      csv_kids = nil

      return nil if (!node.children?)

      csv_kids = node.children()
      csv_kids.each do |kid|
         case (kid.name)
            when "text"
               next
            when "http"
               tmp = ProcessHttpElement(kid)
               csv_hash['stack'].push({'http' => tmp})
            when "controller"
               tmp = GenerateController(kid)
               csv_hash['stack'].push({'controller' => tmp})
            when "loop"
               tmp = GenerateLoop(kid)
               csv_hash['stack'].push({'loop' => tmp})
            when "repeat"
               next if (!kid.children?)
               rep_kids = kid.children()
               rep_kids.each do |rep|
                  next if (rep.name =~ /text/i)
                  tmp = GenericNodeProcess(kid)
                  csv_hash['stack'].push( {'repeat' => tmp} )
               end

            else
               csv_hash["#{kid.name}"] = "#{SafeStr(kid.content)}"
         end
      end

      return csv_hash

   end
   private :ProcessCSVElement

###############################################################################
# ProcessHttpElement -- Method
#     This method processes a test element from the XML test.
#
# Input:
#     node: This is a test node from the XML dom.
#
# Output:
#     Returns a hash containing all the test data from the XML dom.
#
###############################################################################
   def ProcessHttpElement(node)
      data = {
         'assert' => [],
         'regex' => [],
         'timers' => [],
         'upload' => {},
         'has_kids' => false
      }

      kids = node.children()
      kids.each do |kid|
         if (kid.name == "text")
            next
         end

         case (kid.name)
            when "timer"
               next if (!kid.children?)
               tmp = ProcessTimer(kid)
               if (tmp != nil)
                  data['timers'].push(tmp)
               end
            when "asserts"
               if (!kid.children?)
                  next
               end
               data['has_kids'] = true
               ass_hash = Hash.new()
               ass_attrs = kid.attributes()
               ass_attrs = ass_attrs.to_h()
               ass_hash = Marshal.load(Marshal.dump(ass_attrs))
               ass_hash['asserts'] = []

               ass_kids = kid.children()
               ass_kids.each do |ass_node|
                  next if (ass_node.name =~ /text/i)
                  if (ass_node.name =~ /assert/i)
                     ass_hash['asserts'].push("#{SafeStr(ass_node.content)}")
                  else
                     ass_hash["#{ass_node.name}"] = 
                        "#{SafeStr(ass_node.content)}"
                  end
               end
               data['assert'].push(ass_hash)
            when "regex"
               reg_hash = Hash.new()

               if (kid.children?)
                  data['has_kids'] = true
                  regex_kids = kid.children()
                  regex_kids.each do |reg|
                     reg_hash["#{reg.name}"] = "#{SafeStr(reg.content)}"
                  end

                  data['regex'].push(reg_hash)
               end
            when "results"
               if (kid.children?)
                  data['has_kids'] = true
                  data['results'] = {}
                  result_kids = kid.children()
                  result_kids.each do |res|
                     data['results']["#{res.name}"] = "#{SafeStr(res.content)}"
                  end
               end
            when "upload"
               next if (!kid.children?)
               up_kids = kid.children()
               data['upload'] = Hash.new()
               up_kids.each do |up|
                  next if (up.name =~ /text/i)
                  data['upload']["#{up.name}"] = "#{SafeStr(up.content)}"
               end
            when "data"
               attrs = kid.attributes()
               attrs = attrs.to_h()
               data['data'] = {}

               if (kid.children?)
                  data['data']['vars'] = []
                  vars = kid.children()
                  vars.each do |v|
                     vattrs = v.attributes()
                     vattrs = vattrs.to_h()
                     tmp_hash = {}
                     tmp_hash["#{vattrs['name']}"] = "#{SafeStr(v.content)}"
                     next if (!vattrs.key?('name'))
                     data['data']['vars'].push(tmp_hash)
                  end
               end
            else
               data["#{kid.name}"] = "#{SafeStr(kid.content)}"
         end
      end
   
      return data
   end
   private :ProcessHttpElement

###############################################################################
# GenerateAsserts -- Method
#     This method generates jmeter asserts for a test for a given test. 
#
# Input:
#     asserts: A hash of asserts as created by the ProcessTestElement method.
#
# Output: 
#     Returns a string containing the generated jmeter XML to append to the
#     test with the asserts.
#
###############################################################################
   def GenerateAsserts(asserts)
      new_assert = ""
      assert_type = 2
      assert_not = false
      assert_name = "!Unnamed Assert!"

      return nil if (asserts == nil)
      return nil if ( (!asserts.key?('asserts')) || 
         (asserts['asserts'].length < 1) )

      if (asserts.key?('not'))
         if (asserts['not'] =~ /true/i)
            assert_not = true
         end
      end

      if (!asserts.key?('type'))
         assert_type = 2
      else
         if (asserts['type'] =~ /contains/i)
            assert_type = 2
            assert_type = 6 if (assert_not)
         elsif (asserts['type'] =~ /matches/i)
            assert_type = 1
            assert_type = 5 if (assert_not)
         end
      end

      if (asserts.key?('name'))
         assert_name = asserts['name']
      end

      new_assert = <<XML
   <ResponseAssertion guiclass="AssertionGui" testclass="ResponseAssertion"
      testname="Response Assertion: #{assert_name}" enabled="true">
      <stringProp name="Assertion.assume_success">false</stringProp>
      <intProp name="Assertion.test_type">#{assert_type}</intProp>
      <collectionProp name="Asserion.test_strings">\n
XML
      
      asserts['asserts'].each do |ass|
         str = ass.hash() 
         new_assert << "      <stringProp name=\"#{str}\">#{ass}</stringProp>\n"
      end

      new_assert << "      </collectionProp>\n"+
         "<stringProp name=\"Assertion.test_field\">Assertion.response_data"+
         "</stringProp>\n"+
         "    </ResponseAssertion>\n    <hashTree/>\n"

      return new_assert
   end
   private :GenerateAsserts

###############################################################################
# GenerateLoop -- Method
#     This method generates a loop construct containing tests.
#
# Input: 
#     loopdata: This is the XML loop node from the XML dom.
#
# Output:
#     returns a string containing the needed jmeter xml.
# 
###############################################################################
   def GenerateLoop(loopdata)
      loop_hash = {
         'count' => 0,
         'forever' => false,
         'name' => '',
         'tests' => []
      }

      loopdata.each do |loop_node|
         if (loop_node.name =~ /http/i)
            tmp = ProcessHttpElement(loop_node)
            loop_hash['tests'].push(tmp)
         else
            loop_hash["#{loop_node.name}"] = "#{SafeStr(loop_node.content)}"
         end   
      end

      if (loop_hash['forever'].to_s() =~ /false/i)
         loop_hash['forever'] = false
      else
         loop_hash['forever'] = true
      end

      if (loop_hash['forever'])
         loop_hash['count'] = -1
      end

      loop_xml = <<XML
    <LoopController guiclass="LoopControlPanel" testclass="LoopController" 
      testname="Loop Controller: #{loop_hash['name']}" enabled="true">
      <intProp name="LoopController.loops">#{loop_hash['count']}</intProp>
      <boolProp name="LoopController.continue_forever">#{loop_hash['forever']}
      </boolProp>
    </LoopController>
    <hashTree> <!-- Loop: #{loop_hash['name']} start hashTree -->
XML

      return nil if (loop_hash['tests'].length < 1)

      loop_hash['tests'].each do |test|
         test_str = GenerateHttp(test)
         if (test_str != nil)
            loop_xml << test_str
         end
      end
      loop_xml << "    </hashTree> <!-- end loopcontroller hashtree -->\n"

      return loop_xml
   end
   private :GenerateLoop

###############################################################################
# GenerateRegex -- Method
#     This method generates jmeter xml from a test regex.
#
# Input:
#     regex: This is a regex hash.
#
# Output:
#     returns a string containing jmeter xml for a regex.
#
###############################################################################
   def GenerateRegex(regex)
      new_hash = nil
      reg_xml = ""
      regex_defaults = {
         'name' => "Regular Expression Extractor",
         'refname' => 'UNDEFINED_REF_NAME',
         'expression' => '',
         'matchnum' => '0',
         'defaultvalue' => 'REGEX_ERROR',
         'type' => 'body',
         'template' => '$1$',
         'useheaders' => false
      }

      new_hash = Hash.new()
      new_hash = Marshal.load(Marshal.dump(regex_defaults))
      new_hash.merge!(regex)

      if (new_hash.key?('type'))
         case (new_hash['type'])
            when "body"
               new_hash['useheaders'] = "false"
            when "headers"
               new_hash['useheaders'] = "true"
            when "url"
               new_hash['useheaders'] = "URL"
            else
               new_hash['useheaders'] = "false"
         end
      end

   reg_xml = <<XML
    <RegexExtractor guiclass="RegexExtractorGui" testclass="RegexExtractor" 
      testname="Regular Expression Extractor: #{new_hash['nane']}" 
      enabled="true">
      <stringProp name="RegexExtractor.match_number">#{new_hash['matchnum']}</stringProp>
      <stringProp name="RegexExtractor.refname">#{new_hash['refname']}</stringProp>
      <stringProp name="RegexExtractor.default">#{new_hash['defaultvalue']}</stringProp>
      <stringProp name="RegexExtractor.template">#{new_hash['template']}</stringProp>
      <stringProp name="RegexExtractor.useHeaders">#{new_hash['useheaders']}</stringProp>
      <stringProp name="RegexExtractor.regex">#{new_hash['expression']}</stringProp>
    </RegexExtractor>
    <hashTree/>
XML

      return reg_xml
   end
   private :GenerateRegex

###############################################################################
# GenerateHttp -- Method
#     This method generates a jmeter HTTPSampler from a test element.
#
# Input:
#     test: this is the test hash created from the XML dom.
#     thread_group_num: This is the thread group number, not really used yet,
#        but put in for later suupport.
#
# Output:
#     Returns a string containing the jmeter XML for an HTTPSampler.
#
###############################################################################
   def GenerateHttp(test = nil, thread_group_num = 0)
      new_test = ""
      gen_asserts = false
      gen_results = false
      loop_xml = nil
      loop_count = nil
      loop_forever = false
      has_loop = false
      up_file = ""
      up_mime = ""
      up_val = ""

      return nil if (test == nil)
 
      if (!test['upload'].empty?)
         up_file = test['upload']['filename']
         up_mime = test['upload']['mimetype']
         up_val = test['upload']['name_value']
      end

      new_test = <<XML
   <HTTPSampler guiclass="HttpTestSampleGui" testclass="HTTPSampler"
     testname="#{test['name']}" enabled="true">
     <stringProp name="HTTPSampler.domain">#{test['domain']}</stringProp>
     <stringProp name="HTTPSampler.FILE_NAME">#{up_file}</stringProp>
     <stringProp name="HTTPSampler.path">#{test['path']}</stringProp>
     <stringProp name="HTTPSampler.method">#{test['method']}</stringProp>
     <elementProp name="HTTPsampler.Arguments" elementType="Arguments"
       guiclass="HTTPArgumentsPanel" testclass="Arguments" 
       testname="User Defined Variables" enabled="true">        
XML
         if ( (test.key?('data')) && (test['data'].key?('vars')) && 
               (test['data']['vars'].length > 0) )
            new_test << "      <collectionProp name=\"Arguments.arguments\">\n"

            test['data']['vars'].each do |var_hash|
               varkey = var_hash.keys()
               varkey.each do |key|
               end
               varkey = varkey[0]
               varvalue = var_hash[varkey]

               new_test << "      <elementProp name=\"\" elementType="+
               "\"HTTPArgument\">\n"+
               "      <boolProp name=\"HTTPArgument.use_equals\">true"+
               "</boolProp>\n"+
               "      <boolProp name=\"HTTPArgument.always_encode\">false"+
               "</boolProp>\n"+
               "      <stringProp name=\"Argument.metadata\">=</stringProp>\n"+
               "      <stringProp name=\"Argument.name\">#{varkey}"+
               "</stringProp>\n"+
               "      <stringProp name=\"Argument.value\">#{varvalue}"+
               "</stringProp>\n"+
               "      </elementProp>\n"
            end
            new_test << "      </collectionProp>\n"
         else
            new_test << "      <collectionProp name=\"Arguments.arguments\"/>\n"
         end

         new_test << "      </elementProp>\n"+
         "      <stringProp name=\"HTTPSampler.FILE_FIELD\">#{up_val}"+
         "</stringProp>\n"+
         "      <stringProp name=\"HTTPSampler.mimetype\">#{up_mime}"+
         "</stringProp>\n"+
         "      <boolProp name=\"HTTPSampler.auto_redirects\">false</boolProp>"+
         "\n      <boolProp name=\"HTTPSampler.follow_redirects\">true"+
         "</boolProp>\n"+
         "      <stringProp name=\"HTTPSampler.port\"></stringProp>\n"+
         "      <boolProp name=\"HTTPSampler.use_keepalive\">true</boolProp>\n"+
         "      <stringProp name=\"HTTPSampler.monitor\">false</stringProp>\n"+
         "      <stringProp name=\"HTTPSampler.protocol\"></stringProp>\n"
         new_test << "    </HTTPSampler>\n"

         if (test['has_kids'])
            new_test << "    <hashTree> <!-- has kids -->\n" 
         else
            new_test << "    <hashTree/> <!-- donesn't has kids -->\n" 
         end

         if ( (test.key?('regex')) && (test['regex'].length > 0) )
            new_regex = ""
            test['regex'].each do |regex|
               tmp_reg = GenerateRegex(regex)
               if (tmp_reg != nil)
                  new_regex << tmp_reg
               end   
            end
            new_test << new_regex
         end

         if ( (test.key?('timers')) && (test['timers'].length > 0))
            new_timers = ""
            test['timers'].each do |timer|
               tmp_timer = GenerateTimer(timer)
               new_timers << tmp_timer
            end
            new_test << new_timers
         end

         if (test.key?('assert'))
            new_asserts = ""
            test['assert'].each do |ass|
               tmp_assert = GenerateAsserts(ass)
               if (tmp_assert != nil)
                  gen_asserts = true
                  new_asserts << tmp_assert
               end
            end

            new_test << new_asserts
         end

         if (test.key?('results'))
            gen_results = true
            if (!test['results'].key?("result_file"))
               print "Error: Missing 'result_file' key!\n"
               result_file = "report-result.log"
            else
               result_file = test['results']['result_file']
            end

            if (!test['results'].key?('name'))
               test['results']['name'] = "#{test['name']}"
            end

            result_collector = "<ResultCollector "
            result_collector << "guiclass=\"#{test['results']['type']}\" "+
            "testclass=\"ResultCollector\" "+
            "testname=\"#{test['results']['name']}: Results\""+
            " enabled=\"true\">\n"+
            "      <objProp>\n"+
            "      <value class=\"SampleSaveConfiguration\">\n"+
            "      <time>true</time>\n"+
            "      <latency>true</latency>\n"+
            "      <timestamp>true</timestamp>\n"+
            "      <success>true</success>\n"+
            "      <label>true</label>\n"+
            "      <code>true</code>\n"+
            "      <message>true</message>\n"+
            "      <threadName>true</threadName>\n"+
            "      <dataType>true</dataType>\n"+
            "      <encoding>false</encoding>\n"+
            "      <assertions>true</assertions>\n"+
            "      <subresults>true</subresults>\n"+
            "      <responseData>false</responseData>\n"+
            "      <samplerData>false</samplerData>\n"+
            "      <xml>false</xml>\n"+
            "      <fieldNames>false</fieldNames>\n"+
            "      <responseHeaders>false</responseHeaders>\n"+
            "      <requestHeaders>false</requestHeaders>\n"+
            "      <responseDataOnError>false</responseDataOnError>\n"+
            "      <saveAssertionResultsFailureMessage>true"+
            "</saveAssertionResultsFailureMessage>\n"+
            "      <assertionsResultsToSave>0</assertionsResultsToSave>\n"+
            "      </value>\n"+
            "      <name>saveConfig</name>\n"+
            "      </objProp>\n"+
            "      <stringProp name=\"filename\">#{result_file}</stringProp>\n"+
            "      <boolProp name=\"ResultCollector.error_logging\">false"+
            "</boolProp>\n"+
            "      </ResultCollector>\n"+
            "      <hashTree/> <!-- empty result collector hashTree -->"

            new_test << result_collector
         end

         if (test['has_kids'])
            new_test << "    </hashTree> <!-- has kids end -->\n" 
         end

         return new_test 
   end
   private :GenerateHttp

###############################################################################
# GenerateJXM -- Method
#     This method generates an entire jmeter test based on all of the data
#     collected fromt the XML dom.
#
# Input:
#     outputfile: This is the jmeter file to create.
#     data: this is the data that was generated from the GetDataFromTest
#        method.
#
# Output:
#     None.
#
###############################################################################
   def GenerateJXM(outputfile, data)
      fd = nil
      new_test = nil
      thread_group_num = 0
      test_header = ""

      if (!data.key?('testinfo.assertlog'))
         assert_file = "assert.log"
         print "Warning: Failed to find <testinfo>:<asertlog> element.\n"
         print "Setting: default assert lot to file: #{assert_file}.\n"
      else
         assert_file = data['testinfo.assertlog']
      end

      if (!data.key?('testinfo.asserttype'))
         data['testinfo.asserttype'] = "AssertionVisualizer"
      end

      fd = File.new(outputfile, "w+")
      assert_log = <<XML
   <ResultCollector guiclass="#{data['testinfo.asserttype']}" 
      testclass="ResultCollector" testname="Assertion Results" enabled="true">
      <objProp>
      <value class="SampleSaveConfiguration">
      <time>true</time>
      <latency>true</latency>
      <timestamp>true</timestamp>
      <success>true</success>
      <label>true</label>
      <code>true</code>
      <message>true</message>
      <threadName>true</threadName>
      <dataType>true</dataType>
      <encoding>false</encoding>
      <assertions>true</assertions>
      <subresults>true</subresults>
      <responseData>false</responseData>
      <samplerData>false</samplerData>
      <xml>false</xml>
      <fieldNames>false</fieldNames>
      <responseHeaders>false</responseHeaders>
      <requestHeaders>false</requestHeaders>
      <responseDataOnError>false</responseDataOnError>
      <saveAssertionResultsFailureMessage>true
      </saveAssertionResultsFailureMessage>
      <assertionsResultsToSave>0</assertionsResultsToSave>
      </value>
      <name>saveConfig</name>
      </objProp>
      <stringProp name="filename">#{assert_file}</stringProp>
         <boolProp name="ResultCollector.error_logging">false</boolProp>
   </ResultCollector>
   <hashTree/>
XML
      test_header = <<XML
<jmeterTestPlan version="1.2" properties="1.8">
  <hashTree> <!-- Main hash tree --> 
    <TestPlan guiclass="TestPlanGui" testclass="TestPlan" 
      testname="#{data['testinfo.name']}" enabled="true">
      <boolProp name="TestPlan.functional_mode">true</boolProp>
      <stringProp name="TestPlan.comments"></stringProp>
      <stringProp name="TestPlan.user_define_classpath"></stringProp>
      <boolProp name="TestPlan.serialize_threadgroups">false</boolProp>
      <elementProp name="TestPlan.user_defined_variables" 
      elementType="Arguments" guiclass="ArgumentsPanel" 
      testclass="Arguments" testname="User Defined Variables" 
      enabled="true">
      <collectionProp name="Arguments.arguments"/>
      </elementProp>
    </TestPlan>
    <hashTree> <!-- Start test plan hash tree -->
#{assert_log}
    <ThreadGroup guiclass="ThreadGroupGui" testclass="ThreadGroup" 
      testname="Thread Group [#{thread_group_num}]: #{data['testinfo.name']}" 
      enabled="true">
      <boolProp name="ThreadGroup.scheduler">false</boolProp>
      <stringProp name="ThreadGroup.num_threads">#{data['testinfo.numthreads']}</stringProp>
      <stringProp name="ThreadGroup.duration"></stringProp>
      <stringProp name="ThreadGroup.delay"></stringProp>
      <longProp name="ThreadGroup.start_time">#{Time.now().to_i}</longProp>
      <stringProp name="ThreadGroup.on_sample_error">continue</stringProp>
      <stringProp name="ThreadGroup.ramp_time">1</stringProp>
      <elementProp name="ThreadGroup.main_controller" 
        elementType="LoopController" guiclass="LoopControlPanel" 
        testclass="LoopController" testname="Loop Controller" enabled="true">
        <stringProp name="LoopController.loops">1</stringProp>
        <boolProp name="LoopController.continue_forever">false</boolProp>
      </elementProp>
      <longProp name="ThreadGroup.end_time">#{Time.now().to_i}</longProp>
    </ThreadGroup>
   <hashTree> <!-- start thread group's hash tree -->\n
XML

      fd.write(test_header)

      cookies = <<XML
   <CookieManager guiclass="CookiePanel" testclass="CookieManager" 
      testname="HTTP Cookie Manager" enabled="true">
        <boolProp name="CookieManager.clearEachIteration">false</boolProp>
        <collectionProp name="CookieManager.cookies"/>
    </CookieManager>
    <hashTree/> <!-- empty cookies hash tree -->\n
XML
      fd.write(cookies)
      
      # handle stack #
      data['stack'].each do |item|
         if (item.key?('http'))
            test_str = GenerateHttp(item['http'], thread_group_num)
            if (test_str != nil)
               fd.write(test_str)
            end
         elsif (item.key?('controller'))
            ctrl_str = GenerateController(item['controller'])
            if (ctrl_str != nil)
               fd.write(ctrl_str)
            end
         elsif (item.key?('loop'))
            loop_str = GenerateLoop(item['loop'])
            fd.write(loop_str)
         elsif (item.key?('timer'))
            timer_str = GenerateTimer(item['timer'])
            fd.write(timer_str)
         end
      end

      if (data['csv_stack'].length > 0)
         tmp = "       </hashTree> <!-- end other -->\n"+ 
               "     </hashTree> <!-- end thread group hashtree -->\n"
         fd.write(tmp)
      end

      csv_tests = ""
      data['csv_stack'].each do |csv_hash|
         csv_tests << GenerateCSVData(csv_hash)
      end
      
      fd.write(csv_tests)

      if (data['csv_stack'].length < 1)
         tmp = "       </hashTree> <!-- end other -->\n"+ 
               "     </hashTree> <!-- end thread group hashtree -->\n"
         fd.write(tmp)
      end

      file_footer = <<XML
  </hashTree> <!-- end main hashtree -->
</jmeterTestPlan>
XML
      
      fd.write(file_footer)
      fd.close()

   end
   private :GenerateJXM

###############################################################################
# ParseXML -- Method
#     This method parses the speed test file.
#
# Input:
#     file: This is the xml speed test file to parse.
#
# Output:
#     returns nil on error or an XML Dom object on success.
#
###############################################################################
   def ParseXML(file)
      doc = nil
      
      begin
         LibXML::XML.default_line_numbers = true
         doc = LibXML::XML::Parser.file(file).parse()
      rescue Exception => e
         print "Failed trying to parse XML file: '#{file}'!\n"
         print "--)#{e.message}\n"
      ensure

      end
     
      return doc 

   end
   private :ParseXML

end

