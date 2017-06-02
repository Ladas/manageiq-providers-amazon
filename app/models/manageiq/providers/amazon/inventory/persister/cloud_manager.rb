class ManageIQ::Providers::Amazon::Inventory::Persister::CloudManager < ManageIQ::Providers::Amazon::Inventory::Persister
  def initialize_inventory_collections
    add_inventory_collections(
      cloud,
      %i(vms miq_templates hardwares networks disks availability_zones vm_and_template_labels
         flavors key_pairs orchestration_stacks orchestration_stacks_resources
         orchestration_stacks_outputs orchestration_stacks_parameters orchestration_templates)
    )

    add_inventory_collection(
      cloud.vm_and_miq_template_ancestry(
        :dependency_attributes => {
          :vms           => [collections[:vms]],
          :miq_templates => [collections[:miq_templates]]
        }
      )
    )

    add_inventory_collection(
      cloud.orchestration_stack_ancestry(
        :dependency_attributes => {
          :orchestration_stacks           => [collections[:orchestration_stacks]],
          :orchestration_stacks_resources => [collections[:orchestration_stacks_resources]]
        }
      )
    )

  end

  # def test
  #   t = ComputerSystem.arel_table
  #
  #   t.where(t[:managed_entity_type].eq("ContainerNode").and(t[:managed_entity_id].in(manager.container_nodes.select(:id))))
  #
  #   ComputerSystem.where(:managed_entity_type => "ContainerNode", :managed_entity_id => manager.container_nodes.select(:id)).or(ComputerSystem.where(:managed_entity_type => "Hardware", :managed_entity_id => manager.hardwares.select(:id)))
  #
  #   cs_for(manager, :container_nodes).or(cs_for(manager, :hardwares))
  # end
  #
  def cs_for(manager, relation)
    ComputerSystem.where(
      :managed_entity_type => relation.to_s.singularize.camelize,
      :managed_entity_id   => manager.public_send(relation).select(:id)
    )
  end

  def relation_for_all(manager, rel, relation_symbols)
    relations = relation_symbols.map { |x| public_send(rel, manager, x) }
    relation        = relations.first
    other_relations = relations[1..-1]

    return relation if other_relations.blank?
    other_relations.each { |next_relation| relation = relation.or(next_relation) }
    relation
  end
end
