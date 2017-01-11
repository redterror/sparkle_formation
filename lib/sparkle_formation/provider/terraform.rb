require 'sparkle_formation'

class SparkleFormation
  module Provider
    # Terraform specific implementation
    module Terraform

      # Customized dump to break out templates into consumable structures for
      # passing to the deployment manager API
      #
      # @return [Hash]
      def terraform_dump
        result = non_terraform_dump.to_smash
        Smash.new(
          :parameters => :variable,
          :resources => :resource,
          :outputs => :output
        ).each do |original, updated|
          if(val = result.delete(original))
            result[updated] = val
          end
        end
        if(resources = result.delete(:resource))
          result[:resource] = Smash.new
          resources.each do |r_name, r_info|
            result.set(:resource, r_info[:type], r_name, r_info[:properties])
          end
        end
        result
      end

      # Properly remap dumping methods
      def self.included(klass)
        klass.class_eval do
          alias_method :non_terraform_dump, :dump
          alias_method :dump, :terraform_dump
        end
      end

      # Properly remap dumping methods
      def self.extended(klass)
        klass.instance_eval do
          alias :non_terraform_dump :dump
          alias :dump :terraform_dump
        end
      end

      # @return [String] Type string for terraform stack resource
      # @note Nested templates aren't defined as a specific type thus no "real"
      #   type exists. So we'll create a custom one!
      def stack_resource_type
        'module'
      end

      # Generate policy for stack
      #
      # @return [Hash]
      def generate_policy
        {}
      end

      # Apply deeply nested stacks. This is the new nesting approach and
      # does not bubble parameters up to the root stack. Parameters are
      # isolated to the stack resource itself and output mapping is
      # automatically applied.
      #
      # @yieldparam stack [SparkleFormation] stack instance
      # @yieldparam resource [AttributeStruct] the stack resource
      # @yieldparam s_name [String] stack resource name
      # @yieldreturn [Hash] key/values to be merged into resource properties
      # @return [SparkleFormation::SparkleStruct] compiled structure
      def apply_deep_nesting(*args, &block)
        outputs = collect_outputs
        nested_stacks(:with_resource).each do |stack, resource|
          unless(stack.nested_stacks.empty?)
            stack.apply_deep_nesting(*args)
          end
          stack.compile.parameters.keys!.each do |parameter_name|
            if(output_name = output_matched?(parameter_name, outputs.keys))
              next if outputs[output_name] == stack
              stack_output = stack.make_output_available(output_name, outputs, self)
              # NOTE: Only set value if not already explicitly set
              if(resource.properties.parameters._set(parameter_name).nil?)
                resource.properties.parameters._set(parameter_name, stack_output)
              end
            end
          end
        end
        if(block_given?)
          extract_templates(&block)
        end
        self
      end

      # Forcibly disable shallow nesting
      def apply_shallow_nesting(*args, &block)
        raise NotImplementedError.new 'Shallow nesting is not supported for this provider!'
      end

      # Extract output to make available for stack parameter usage at the
      # current depth
      #
      # @param output_name [String] name of output
      # @param outputs [Hash] listing of outputs
      # @param source_stack [SparkleFormation] requesting stack
      # @reutrn [Hash] reference to output value (used for setting parameter)
      def make_output_available(output_name, outputs, source_stack)
        bubble_path = outputs[output_name].root_path - root_path
        drip_path = root_path - outputs[output_name].root_path
        bubble_path.each_slice(2) do |base_sparkle, ref_sparkle|
          next unless ref_sparkle
          base_sparkle.compile.outputs._set(output_name)._set(
            :value, base_sparkle.compile._stack_output(
              ref_sparkle.name, output_name
            )
          )
        end
        if(bubble_path.empty?)
          if(drip_path.size == 1)
            parent = drip_path.first.parent
            if(parent && !parent.compile.parameters._set(output_name).nil?)
              return compile.parameter!(output_name)
            end
          end
          raise ArgumentError.new "Failed to detect available bubbling path for output `#{output_name}`. " <<
            'This may be due to a circular dependency! ' <<
            "(Output Path: #{outputs[output_name].root_path.map(&:name).join(' > ')} " <<
            "Requester Path: #{root_path.map(&:name).join(' > ')})"
        end
        result = source_stack.compile._stack_output(bubble_path.first.name, output_name)
        if(drip_path.size > 1)
          parent = drip_path.first.parent
          drip_path.unshift(parent) if parent
          drip_path.each_slice(2) do |base_sparkle, ref_sparkle|
            next unless ref_sparkle
            base_sparkle.compile.resources[ref_sparkle.name].properties.parameters.value._set(output_name, result)
            ref_sparkle.compile.parameters._set(output_name).type 'string' # TODO: <<<<------ type check and prop
            result = compile._parameter(output_name)
          end
        end
        result
      end

    end
  end
end
