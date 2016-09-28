class ManageIQ::Providers::Amazon::NetworkManager::CloudSubnet < ::CloudSubnet
  class DtoCollection < ::DtoCollection
    class Dto < ::DtoCollection::Dto
      attr_accessor :type, :ems_ref, :name, :cidr, :status, :availability_zone, :cloud_network
    end
  end
end
