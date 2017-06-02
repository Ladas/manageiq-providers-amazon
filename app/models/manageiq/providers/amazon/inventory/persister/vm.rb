# frozen_string_literal: true
class ManageIQ::Providers::Amazon::Inventory::Persister::Vm < ManageIQ::Providers::Amazon::Inventory::Persisters
  def initialize_inventory_collections
    instances_refs << target.ems_ref

    add_vms_inventory_collections(instances_refs)
    add_hardwares_inventory_collections(instances_refs)

    add_remaining_inventory_collections(:strategy => :local_db_find_references)
  end

  def instances
    HashCollection.new(
      aws_ec2.instances(:filters => [{ :name => 'instance-id', :values => instances_refs}])
    )
  end

  def add_vms_inventory_collections(manager_refs)
    return if manager_refs.blank?

    add_inventory_collection(
      vms_init_data(
        :arel     => ems.vms.where(:ems_ref => manager_refs),
        :strategy => :local_db_find_missing_references
      )
    )
    add_inventory_collection(
      disks_init_data(
        :arel     => ems.disks.joins(:hardware => :vm_or_template).where(
          :hardware => {'vms' => {:ems_ref => manager_refs}}
        ),
        :strategy => :local_db_find_missing_references
      )
    )
    add_inventory_collection(
      networks_init_data(
        :arel     => ems.networks.joins(:hardware => :vm_or_template).where(
          :hardware => {'vms' => {:ems_ref => manager_refs}}
        ),
        :strategy => :local_db_find_missing_references
      )
    )
  end

  def add_hardwares_inventory_collections(manager_refs)
    return if manager_refs.blank?

    add_inventory_collection(
      hardwares_init_data(
        :arel     => ems.hardwares.joins(:vm_or_template).where(
          :vms => {:ems_ref => manager_refs}
        ),
        :strategy => :local_db_find_missing_references
      )
    )
  end
end
