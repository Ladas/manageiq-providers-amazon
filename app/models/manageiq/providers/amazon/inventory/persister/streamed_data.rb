class ManageIQ::Providers::Amazon::Inventory::Persister::StreamedData < ManageIQ::Providers::Amazon::Inventory::Persister::TargetCollection
  def saver_strategy
    # :concurrent_safe
    # :default
    :concurrent_safe_batch
  end

  def references(_collection)
    # References are provided by loading it from serialized Persistor YAML
    []
  end

  def name_references(_collection)
    # References are provided by loading it from serialized Persistor YAML
    []
  end

  def initialize_inventory_collections_old
    # Cloud + Network + Storage Persisters
    add_inventory_collections(
      cloud,
      %i(vms miq_templates hardwares networks disks availability_zones vm_and_template_labels
         flavors key_pairs orchestration_stacks orchestration_stacks_resources
         orchestration_stacks_outputs orchestration_stacks_parameters orchestration_templates),
      :complete       => false,
      :saver_strategy => :concurrent_safe
    )

    add_inventory_collections(
      network,
      %i(cloud_subnet_network_ports network_ports floating_ips cloud_subnets cloud_networks security_groups
         firewall_rules load_balancers load_balancer_pools load_balancer_pool_members load_balancer_pool_member_pools
         load_balancer_listeners load_balancer_listener_pools load_balancer_health_checks
         load_balancer_health_check_members),
      :complete       => false,
      :saver_strategy => :concurrent_safe,
      :parent         => manager.network_manager
    )

    add_inventory_collections(
      storage,
      %i(cloud_volumes cloud_volume_snapshots),
      :complete       => false,
      :saver_strategy => :concurrent_safe,
      :parent         => manager.ebs_storage_manager
    )

    # TODO(lsmola) need to enable S3
    # add_inventory_collections(
    #   storage,
    #   %i(cloud_object_store_containers cloud_object_store_objects),
    #   :complete => false,
    #   :strategy => :stream_data,
    #   :parent   => manager.s3_storage_manager
    # )

    # Custom nodes for optimized saving of Ancestry
    # add_inventory_collection(
    #   cloud.vm_and_miq_template_ancestry(
    #     :dependency_attributes => {
    #       :vms           => [collections[:vms]],
    #       :miq_templates => [collections[:miq_templates]]
    #     },
    #   )
    # )
    #
    # add_inventory_collection(
    #   cloud.orchestration_stack_ancestry(
    #     :dependency_attributes => {
    #       :orchestration_stacks           => [collections[:orchestration_stacks]],
    #       :orchestration_stacks_resources => [collections[:orchestration_stacks_resources]]
    #     }
    #   )
    # )
  end
end
