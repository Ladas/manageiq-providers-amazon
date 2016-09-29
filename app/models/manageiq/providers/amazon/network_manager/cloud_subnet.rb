class ManageIQ::Providers::Amazon::NetworkManager::CloudSubnet < ::CloudSubnet
  class DtoCollection < ::DtoCollection

    def dependencies
      [:cloud_networks]
    end

    class Dto < ::DtoCollection::Dto
      attr_accessor :type, :ems_ref, :name, :cidr, :status, :availability_zone, :cloud_network
    end
  end
end
