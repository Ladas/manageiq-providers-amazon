class ManageIQ::Providers::Amazon::NetworkManager::NetworkPort < ::NetworkPort
  class DtoCollection
    include Enumerable
    def initialize(data = nil)
      @data = data || []
      # @data_index =
    end

    def <<(dto)
      @data_index[provider_uuid] = dto
      @data << dto
    end

    def provider_uuid
      provider_uuid_attributes.map{|attribute| send(attribute)}.join("__")
    end

    def provider_uuid_attributes
      [:ems_ref]
    end

    def lazy_find(ems_ref)
      ->(ems_ref) {
        @data_index[ems_ref]
      }
    end

    def each(*args, &block)
      @data.each(*args, &block)
    end
  end

  class Dto
    include ActiveModel::Model
    attr_accessor :type, :name, :ems_ref, :status, :mac_address, :device_owner, :device_ref, :device, :cloud_subnet_network_ports, :security_groups
  end
end
