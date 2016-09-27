class ManageIQ::Providers::Amazon::NetworkManager::NetworkPort < ::NetworkPort
  class DtoCollection
    include Enumerable
    def initialize(data)
      @data = data
      # @data_index =
    end

    def each(*args, &block)
      @data.each(*args, &block)
    end

    def fetch_path(*args)
      
    end
  end
  
  class Dto
    include ActiveModel::Model
    attr_accessor :type, :name, :ems_ref, :status, :mac_address, :device_owner, :device_ref, :device, :cloud_subnet_network_ports, :security_groups
  end
end
