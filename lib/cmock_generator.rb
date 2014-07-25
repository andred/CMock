# ==========================================
#   CMock Project - Automatic Mock Generation for C
#   Copyright (c) 2007 Mike Karlesky, Mark VanderVoord, Greg Williams
#   [Released under MIT License. Please refer to license.txt for details]
# ==========================================

$here = File.dirname __FILE__

class CMockGenerator

  attr_accessor :config, :file_writer, :module_name, :clean_mock_name, :mock_name, :utils, :plugins, :ordered

  def initialize(config, file_writer, utils, plugins)
    @file_writer = file_writer
    @utils       = utils
    @plugins     = plugins
    @config      = config
    @prefix      = @config.mock_prefix
    @ordered     = @config.enforce_strict_ordering
    @framework   = @config.framework.to_s

    @includes_h_pre_orig_header  = (@config.includes || @config.includes_h_pre_orig_header || []).map{|h| h =~ /</ ? h : "\"#{h}\""}
    @includes_h_post_orig_header = (@config.includes_h_post_orig_header || []).map{|h| h =~ /</ ? h : "\"#{h}\""}
    @includes_c_pre_header       = (@config.includes_c_pre_header || []).map{|h| h =~ /</ ? h : "\"#{h}\""}
    @includes_c_post_header      = (@config.includes_c_post_header || []).map{|h| h =~ /</ ? h : "\"#{h}\""}
  end

  def create_mock(module_name, parsed_stuff)
    @module_name = module_name
    @mock_name   = @prefix + @module_name
    @clean_mock_name = @mock_name.gsub(/(?:-|\s+)/, "_")
    create_mock_header_file(parsed_stuff)
    create_mock_source_file(parsed_stuff)
  end

  private if $ThisIsOnlyATest.nil? ##############################

  def create_mock_header_file(parsed_stuff)
    @file_writer.create_file(@mock_name + ".h") do |file, filename|
      create_mock_header_header(file, filename)
      create_mock_header_service_call_declarations(file)
      create_typedefs(file, parsed_stuff[:typedefs])
      parsed_stuff[:functions].each do |function|
        file << @plugins.run(:mock_function_declarations, function)
      end
      create_mock_header_footer(file)
    end
  end

  def create_mock_source_file(parsed_stuff)
    @file_writer.create_file(@mock_name + ".c") do |file, filename|
      create_source_header_section(file, filename)
      create_instance_structure(file, parsed_stuff[:functions])
      create_extern_declarations(file)
      create_mock_verify_function(file, parsed_stuff[:functions])
      create_mock_init_function(file)
      create_mock_destroy_function(file, parsed_stuff[:functions])
      parsed_stuff[:functions].each do |function|
        create_mock_implementation(file, function)
        create_mock_interfaces(file, function)
      end
    end
  end

  def create_mock_header_header(file, filename)
    define_name   = @clean_mock_name.gsub(/[-\/\\\.\,\s]+/,'_').upcase
    orig_filename = filename[@config.mock_prefix.size..-1]
    file << "/* AUTOGENERATED FILE. DO NOT EDIT. */\n"
    file << "#ifndef _#{define_name}_H\n"
    file << "#define _#{define_name}_H\n\n"
    @includes_h_pre_orig_header.each {|inc| file << "#include #{inc}\n"}
    file << "#include \"#{orig_filename}\"\n"
    @includes_h_post_orig_header.each {|inc| file << "#include #{inc}\n"}
    plugin_includes = @plugins.run(:include_files)
    file << plugin_includes if (!plugin_includes.empty?)
    file << "\n"
    file << "/* Ignore the following warnings, since we are copying code */\n"
    file << "#pragma GCC diagnostic ignored \"-Wunknown-pragmas\"\n"
    file << "#pragma GCC diagnostic ignored \"-Wduplicate-decl-specifier\"\n"
    file << "\n"
  end

  def create_typedefs(file, typedefs)
    file << "\n"
    typedefs.each {|typedef| file << "#{typedef}\n" }
    file << "\n\n"
  end

  def create_mock_header_service_call_declarations(file)
    file << "void #{@clean_mock_name}_Init(void);\n"
    file << "void #{@clean_mock_name}_Destroy(void);\n"
    file << "void #{@clean_mock_name}_Verify(void);\n\n"
  end

  def create_mock_header_footer(header)
    header << "\n#endif\n"
  end

  def create_source_header_section(file, filename)
    header_file = filename.gsub(".c",".h")
    file << "/* AUTOGENERATED FILE. DO NOT EDIT. */\n"
    file << "#include <string.h>\n"
    file << "#include <stdlib.h>\n"
    file << "#include <setjmp.h>\n"
    file << "#include \"#{@framework}.h\"\n"
    file << "#include \"cmock.h\"\n"
    @includes_c_pre_header.each {|inc| file << "#include #{inc}\n"}
    file << "#include \"#{header_file}\"\n"
    @includes_c_post_header.each {|inc| file << "#include #{inc}\n"}
    file << "\n"
  end

  def create_instance_structure(file, functions)
    functions.each do |function|
      file << "typedef struct _CMOCK_#{function[:name]}_CALL_INSTANCE\n{\n"
      file << "  UNITY_LINE_TYPE LineNumber;\n"
      file << @plugins.run(:instance_typedefs, function)
      file << "\n} CMOCK_#{function[:name]}_CALL_INSTANCE;\n\n"
    end
    file << "static struct #{@clean_mock_name}Instance\n{\n"
    if (functions.size == 0)
      file << "  unsigned char placeHolder;\n"
    end
    functions.each do |function|
      file << @plugins.run(:instance_structure, function)
      file << "  CMOCK_MEM_INDEX_TYPE #{function[:name]}_CallInstance;\n"
    end
    file << "} Mock;\n\n"
  end

  def create_extern_declarations(file)
    file << "extern jmp_buf AbortFrame;\n"
    if (@ordered)
      file << "extern int GlobalExpectCount;\n"
      file << "extern int GlobalVerifyOrder;\n"
    end
    file << "\n"
  end

  def create_mock_verify_function(file, functions)
    file << "void #{@clean_mock_name}_Verify(void)\n{\n"
    verifications = functions.collect {|function| @plugins.run(:mock_verify, function)}.join
    file << "  UNITY_LINE_TYPE cmock_line = TEST_LINE_NUM;\n" unless verifications.empty?
    file << verifications
    file << "}\n\n"
  end

  def create_mock_init_function(file)
    file << "void #{@clean_mock_name}_Init(void)\n{\n"
    file << "  #{@clean_mock_name}_Destroy();\n"
    file << "}\n\n"
  end

  def create_mock_destroy_function(file, functions)
    file << "void #{@clean_mock_name}_Destroy(void)\n{\n"
    file << "  CMock_Guts_MemFreeAll();\n"
    file << "  memset(&Mock, 0, sizeof(Mock));\n"
    file << functions.collect {|function| @plugins.run(:mock_destroy, function)}.join
    if (@ordered)
      file << "  GlobalExpectCount = 0;\n"
      file << "  GlobalVerifyOrder = 0;\n"
    end
    file << "}\n\n"
  end

  def create_mock_implementation(file, function)
    # prepare return value and arguments
    function_mod_and_rettype = (function[:modifier].empty? ? '' : "#{function[:modifier]} ") +
                               (function[:return][:type]) +
                               (function[:c_calling_convention] ? " #{function[:c_calling_convention]}" : '')
    args_string = function[:args_string]
    args_string += (", " + function[:var_arg]) unless (function[:var_arg].nil?)

    # Create mock function
    file << "#{function_mod_and_rettype} #{function[:name]}(#{args_string})\n"
    file << "{\n"
    file << "  UNITY_LINE_TYPE cmock_line = TEST_LINE_NUM;\n"
    file << "  CMOCK_#{function[:name]}_CALL_INSTANCE* cmock_call_instance = (CMOCK_#{function[:name]}_CALL_INSTANCE*)CMock_Guts_GetAddressFor(Mock.#{function[:name]}_CallInstance);\n"
    file << "  Mock.#{function[:name]}_CallInstance = CMock_Guts_MemNext(Mock.#{function[:name]}_CallInstance);\n"
    file << @plugins.run(:mock_implementation_precheck, function)
    file << "  UNITY_TEST_ASSERT_NOT_NULL(cmock_call_instance, cmock_line, \"Function '#{function[:name]}' called more times than expected.\");\n"
    file << "  cmock_line = cmock_call_instance->LineNumber;\n"
    if (@ordered)
      file << "  if (cmock_call_instance->CallOrder > ++GlobalVerifyOrder)\n"
      file << "    UNITY_TEST_FAIL(cmock_line, \"Function '#{function[:name]}' called earlier than expected.\");\n"
      file << "  if (cmock_call_instance->CallOrder < GlobalVerifyOrder)\n"
      file << "    UNITY_TEST_FAIL(cmock_line, \"Function '#{function[:name]}' called later than expected.\");\n"
      # file << "  UNITY_TEST_ASSERT((cmock_call_instance->CallOrder == ++GlobalVerifyOrder), cmock_line, \"Out of order function calls. Function '#{function[:name]}'\");\n"
    end
    return_type_cast = function[:return][:const?] ? "(const #{function[:return][:type]})" : ''
    file << @plugins.run(:mock_implementation, function)
    file << "  return #{return_type_cast}cmock_call_instance->ReturnVal;\n" unless (function[:return][:void?])
    file << "}\n\n"
  end

  def create_mock_interfaces(file, function)
    file << @utils.code_add_argument_loader(function)
    file << @plugins.run(:mock_interfaces, function)
  end
end
