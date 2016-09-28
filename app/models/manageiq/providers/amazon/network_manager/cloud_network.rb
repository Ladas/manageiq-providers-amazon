class ManageIQ::Providers::Amazon::NetworkManager::CloudNetwork < ::CloudNetwork
  class DtoCollection < ::DtoCollection
    class Dto < ::DtoCollection::Dto
      attr_accessor :type, :ems_ref, :name, :cidr ,:status,:enabled, :orchestration_stack, :cloud_subnets
    end
  end
end
