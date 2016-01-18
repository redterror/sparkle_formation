require 'sparkle_formation'

class SparkleFormation

  # Resources helper
  class Resources

    # Azure specific resources collection
    class Azure < Resources

      # String to split for resource namespacing
      RESOURCE_TYPE_NAMESPACE_SPLITTER = '/'

      class << self

        include Bogo::Memoization

        # Load the builtin AWS resources
        #
        # @return [TrueClass]
        def load!
          memoize(:azure_resources, :global) do
            load(
              File.join(
                File.dirname(__FILE__),
                'azure_resources.json'
              )
            )
            true
          end
        end

        # Auto load data when included
        def included(_klass)
          load!
        end

      end

    end
  end
end