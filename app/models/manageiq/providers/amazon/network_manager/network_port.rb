class ManageIQ::Providers::Amazon::NetworkManager::NetworkPort < ::NetworkPort
  class DtoCollection < ::DtoCollection
    class Dto < ::DtoCollection::Dto
      attr_accessor :type, :name, :ems_ref, :status, :mac_address, :device_owner, :device_ref, :device, :cloud_subnet_network_ports, :security_groups
    end
  end
end
