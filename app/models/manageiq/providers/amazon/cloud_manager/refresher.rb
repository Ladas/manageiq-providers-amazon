class ManageIQ::Providers::Amazon::CloudManager::Refresher < ManageIQ::Providers::BaseManager::Refresher
  include ::EmsRefresh::Refreshers::EmsRefresherMixin

  def collect_inventory_for_targets(ems, targets)
    targets_with_data = targets.collect do |target|
      target_name = target.try(:name) || target.try(:event_type)

      _log.info "Filtering inventory for #{target.class} [#{target_name}] id: [#{target.id}]..."

      inventory = if refresher_options.try(:[], :inventory_object_refresh)
                    ManageIQ::Providers::Amazon::Inventory::Factory.inventory(ems, target)
                  else
                    nil
                  end

      _log.info "Filtering inventory...Complete"
      [target, inventory]
    end

    targets_with_data
  end

  def parse_targeted_inventory(ems, _target, inventory)
    log_header = format_ems_for_logging(ems)
    _log.debug "#{log_header} Parsing inventory..."
    hashes, = Benchmark.realtime_block(:parse_inventory) do
      if refresher_options.try(:[], :inventory_object_refresh)
        ManageIQ::Providers::Amazon::CloudManager::RefreshParserInventoryObject.new(inventory).populate_inventory_collections

        if inventory.kind_of?(ManageIQ::Providers::Amazon::Inventory::Targets::TargetCollection)
          # For EmsEventCollection, we want to parse everything, regardless whether it belongs to Cloud or Network
          # Manager
          ManageIQ::Providers::Amazon::NetworkManager::RefreshParserInventoryObject.new(inventory).populate_inventory_collections
        end

        inventory.inventory_collections
      else
        ManageIQ::Providers::Amazon::CloudManager::RefreshParser.ems_inv_to_hashes(ems, refresher_options)
      end
    end
    _log.debug "#{log_header} Parsing inventory...Complete"

    hashes
  end

  def preprocess_targets
    @targets_by_ems_id.each do |ems_id, targets|
      ems             = @ems_by_ems_id[ems_id]
      targets_for_log = targets.map { |t| "#{t.class} [#{t.name}] id [#{t.id}] " }
      _log.info "TARGETBEFORE to full refresh for EMS: [#{ems.name}], id: [#{ems.id}], from targets: #{targets_for_log}"

      if targets.any? { |t| t.kind_of?(ExtManagementSystem) }
        ems             = @ems_by_ems_id[ems_id]
        targets_for_log = targets.map { |t| "#{t.class} [#{t.name}] id [#{t.id}] " }
        _log.info "Defaulting to full refresh for EMS: [#{ems.name}], id: [#{ems.id}], from targets: #{targets_for_log}" if targets.length > 1
      end

      # We want all targets of class EmsEvent to be merged into one target, so they can be refreshed together, otherwise
      # we could be missing some crosslinks in the refreshed data
      all_targets, sub_ems_targets = targets.partition { |x| x.kind_of?(ExtManagementSystem) }

      unless sub_ems_targets.blank?
        ems_event_collection = ManageIQ::Providers::Amazon::Inventory::TargetCollection.new(sub_ems_targets)
        all_targets << ems_event_collection
      end

      targets_for_log = all_targets.map { |t| "#{t.class} [#{t.name}] id [#{t.id}] " }
      _log.info "TARGETAFTER to full refresh for EMS: [#{ems.name}], id: [#{ems.id}], from targets: #{targets_for_log}"

      @targets_by_ems_id[ems_id] = all_targets
    end

    super
  end

  # TODO(lsmola) NetworkManager, remove this once we have a full representation of the NetworkManager.
  # NetworkManager should refresh base on its own conditions
  def save_inventory(ems, target, inventory_collections)
    EmsRefresh.save_ems_inventory(ems, inventory_collections)
    EmsRefresh.queue_refresh(ems.network_manager) if target.kind_of?(ManageIQ::Providers::BaseManager)
  end

  def post_process_refresh_classes
    [::Vm]
  end
end
