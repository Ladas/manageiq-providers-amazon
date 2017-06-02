require_relative "../../aws_refresher_spec_common"
require_relative "../../aws_refresher_spec_counts"
require 'manageiq_performance'

describe ManageIQ::Providers::Amazon::CloudManager::Refresher do
  include AwsRefresherSpecCommon
  include AwsRefresherSpecCounts

  before(:each) do
    @ems = FactoryGirl.create(:ems_amazon_with_vcr_authentication)
  end

  # Test all kinds of graph refreshes, graph refresh, graph with recursive saving strategy
  [{:inventory_object_refresh => true},
  #{:inventory_object_saving_strategy => :recursive, :inventory_object_refresh => true},
  ].each do |inventory_object_settings|
    context "with settings #{inventory_object_settings}" do
      before(:each) do
        settings                                  = OpenStruct.new
        settings.inventory_object_saving_strategy = inventory_object_settings[:inventory_object_saving_strategy]
        settings.inventory_object_refresh         = inventory_object_settings[:inventory_object_refresh]
        settings.allow_targeted_refresh           = true
        settings.get_private_images               = true
        settings.get_shared_images                = true
        settings.get_public_images                = false

        allow(Settings.ems_refresh).to receive(:ec2).and_return(settings)
      end

      it "test stuff" do
        timings = nil
        total_elements             = 1000
        total_not_deleted_elements = 2
        ActiveRecord::Base.logger  = Logger.new(STDOUT)

        # 1st refresh creating records
        ManageIQPerformance.profile do
          _, timings = Benchmark.realtime_block(:ems_total_refresh) do
            generate_batches_od_data(:ems_name => @ems.name, :total_elements => total_elements, :batch_size => 10000000)
          end
        end
        $log.info "#{@ems.id} LADAS_TOTAL_BENCH 1st refresh #{timings.inspect}"
        # assert_counts_and_relations(total_elements,
        #                             total_elements,
        #                             0
        # )

        # 2st refresh updating records
        ManageIQPerformance.profile do
          _, timings = Benchmark.realtime_block(:ems_total_refresh) do
            generate_batches_od_data(:ems_name => @ems.name, :total_elements => total_elements, :batch_size => 10000000)
          end
        end
        $log.info "#{@ems.id} LADAS_TOTAL_BENCH 2nd refresh #{timings.inspect}"
        assert_counts_and_relations(total_elements,
                                    total_elements,
                                    0
        )

        # # 2nd refresh doing partial delete of records
        # ManageIQPerformance.profile do
        #   _, timings = Benchmark.realtime_block(:ems_total_refresh) do
        #     generate_delete_complement_of_data(:ems_name => @ems.name, :total_not_deleted_elements => total_not_deleted_elements)
        #   end
        # end
        # $log.info "#{@ems.id} LADAS_TOTAL_BENCH 2rd refresh #{timings.inspect}"
        # assert_counts_and_relations(total_not_deleted_elements,
        #                             total_not_deleted_elements,
        #                             total_elements - total_not_deleted_elements
        # )
        #
        # # 3rd refresh doing update and create/reconnect
        # ManageIQPerformance.profile do
        # _, timings = Benchmark.realtime_block(:ems_total_refresh) do
        #   generate_batches_od_data(:ems_name => @ems.name, :total_elements => total_elements, :batch_size => 1000)
        # end
        # end
        # $log.info "#{@ems.id} LADAS_TOTAL_BENCH 3rd refresh #{timings.inspect}"
        # assert_counts_and_relations(total_elements,
        #                             total_elements,
        #                             total_elements - total_not_deleted_elements
        # )

        puts "finished"
      end
    end
  end

  def generate_delete_complement_of_data(ems_name:, total_not_deleted_elements:)
    ems = ExtManagementSystem.find_by(:name => ems_name)

    complement_delete_entity(ems, :vm, total_not_deleted_elements)
    complement_delete_entity(ems, :miq_template, total_not_deleted_elements)
    complement_delete_entity(ems, :availability_zone, total_not_deleted_elements)
    complement_delete_entity(ems, :flavor, total_not_deleted_elements)
    complement_delete_entity(ems, :orchestration_stack, total_not_deleted_elements)
    complement_delete_entity(ems, :key_pair, total_not_deleted_elements)
  end

  def complement_delete_entity(ems, entity_name, total_not_deleted_elements)
    persister = ManageIQ::Providers::Amazon::Inventory::Persister::StreamedData.new(
      ems, ems
    )

    persister.send(entity_name.to_s.pluralize).all_manager_uuids = (1..total_not_deleted_elements).map do |index|
      "#{entity_name}_#{index}"
    end

    persister = ManagerRefresh::Inventory::Persister.from_yaml(persister.to_yaml)

    ManagerRefresh::SaveInventory.save_inventory(
      persister.manager,
      persister.inventory_collections
    )
  end

  def generate_batches_od_data(ems_name:, total_elements:, batch_size: 1000)
    ems       = ExtManagementSystem.find_by(:name => ems_name)
    persister = ManageIQ::Providers::Amazon::Inventory::Persister::StreamedData.new(
      ems, ems
    )
    count     = 1

    persister, count = process_entity(ems, :vm, persister, count, total_elements, batch_size)
    persister, count = process_entity(ems, :miq_template, persister, count, total_elements, batch_size)
    persister, count = process_entity(ems, :availability_zone, persister, count, total_elements, batch_size)
    persister, count = process_entity(ems, :flavor, persister, count, total_elements, batch_size)
    persister, count = process_entity(ems, :orchestration_stack, persister, count, total_elements, batch_size)
    persister, count = process_entity(ems, :key_pair, persister, count, total_elements, batch_size)

    # Send or update the rest which is batch smaller than the batch size
    send_or_update(ems, :key_pair, persister, :rest, batch_size)
  end

  def process_entity(ems, entity_name, starting_persister, starting_count, total_elements, batch_size)
    persister = starting_persister
    count     = starting_count

    (1..total_elements).each do |index|
      send("parse_#{entity_name.to_s}", index, persister)
      persister, count = send_or_update(ems, entity_name, persister, count, batch_size)
    end

    return persister, count
  end

  def send_or_update(ems, entity_name, persister, count, batch_size)
    if count == :rest || count >= batch_size
      ############################ Replace by sending to kafka and use the saving code on the other side START #########
      persister = ManagerRefresh::Inventory::Persister.from_yaml(persister.to_yaml)

      _, timings = Benchmark.realtime_block(:ems_refresh) do
        ManagerRefresh::SaveInventory.save_inventory(
          persister.manager,
          persister.inventory_collections
        )
      end

      $log.info "#{ems.id} LADAS_BENCH #{timings.inspect}"
      ############################ Replace by sending to kafka and use the saving code on the other side END ###########

      # And and create new persistor so the old one with data can be GCed
      return_persister = ManageIQ::Providers::Amazon::Inventory::Persister::StreamedData.new(
        ems, ems
      )
      return_count     = 1
    else
      return_persister = persister

      addition = case entity_name
                 when :vm
                   2
                 else
                   1
                 end

      return_count = count + addition
    end

    return return_persister, return_count
  end

  def parse_orchestration_stack(index, persister)
    parent = index > 2 ? persister.orchestration_stacks.lazy_find("orchestration_stack_#{index - 1}") : nil

    persister.orchestration_stacks.build(
      :ems_ref       => "orchestration_stack_#{index}",
      :name          => "orchestration_stack_#{index}_name",
      :description   => "orchestration_stack_#{index}_description",
      :status        => "orchestration_stack_#{index}_ok",
      :status_reason => "orchestration_stack_#{index}_status_reason",
      :parent        => parent
    )
  end

  def parse_vm(index, persister)
    persister.vms.build(
      :ems_ref             => "vm_#{index}",
      :uid_ems             => "vm_#{index}_uid_ems",
      :name                => "vm_#{index}_name",
      :vendor              => "amazon",
      :raw_power_state     => "vm_#{index} status",
      :boot_time           => Time.now, #nil, # Time.now this will cause that dta are updated in second + refresh
      :availability_zone   => persister.availability_zones.lazy_find("availability_zone_#{index}"),
      :flavor              => persister.flavors.lazy_find("flavor_#{index}"),
      :genealogy_parent    => persister.miq_templates.lazy_find("miq_template_#{index}"),
      # :key_pairs           => [persister.key_pairs.lazy_find("key_pair_#{index}")],
      :location            => persister.networks.lazy_find("miq_template_#{index}__public", :key => :hostname, :default => 'unknown'),
      :orchestration_stack => persister.orchestration_stacks.lazy_find("orchestration_stack_#{index}")
    )

    parse_hardware(index, persister)
  end

  def parse_miq_template(index, persister)
    persister.miq_templates.build(
      :ems_ref            => "miq_template_#{index}",
      :uid_ems            => "miq_template_#{index}_uid_ems",
      :name               => "miq_template_#{index}_name",
      :location           => "miq_template_#{index}_location",
      :vendor             => "amazon",
      :raw_power_state    => "never",
      :template           => true,
      :publicly_available => true
    )
  end

  def parse_flavor(index, persister)
    persister.flavors.build(
      :ems_ref                  => "flavor_#{index}",
      :name                     => "flavor_#{index}_name",
      :description              => "flavor_#{index}_description",
      :enabled                  => true,
      :cpus                     => 1,
      :cpu_cores                => 1,
      :memory                   => 1024,
      :supports_32_bit          => true,
      :supports_64_bit          => true,
      :supports_hvm             => true,
      :supports_paravirtual     => false,
      :block_storage_based_only => true,
      :cloud_subnet_required    => true,
      :ephemeral_disk_size      => 10,
      :ephemeral_disk_count     => 1
    )
  end

  def parse_availability_zone(index, persister)
    persister.availability_zones.build(
      :ems_ref => "availability_zone_#{index}",
      :name    => "availability_zone_#{index}_name"
    )
  end

  def parse_hardware(index, persister)
    persister.hardwares.build(
      :vm_or_template       => persister.vms.lazy_find("vm_#{index}"),
      :bitness              => 64,
      :virtualization_type  => "hvm",
      :root_device_type     => "root_device_type",
      :cpu_sockets          => 4,
      :cpu_cores_per_socket => 1,
      :cpu_total_cores      => 6,
      :memory_mb            => 600,
      :disk_capacity        => 200,
      :guest_os             => persister.hardwares.lazy_find("miq_template_#{index}", :key => :guest_os),
    )
  end

  def parse_key_pair(index, persister)
    persister.key_pairs.build(
      :name        => "key_pair_#{index}",
      :fingerprint => "key_pair_#{index}_fingerprint",
      :authtype    => "keypair",
      :userid      => "20"
    )
  end

  def assert_counts_and_relations(total_elements = 0, total_not_deleted_elements = 0, total_disconnected_elements = 0)
    @ems.reload

    # vm = Vm.find_by(:ems_ref => "vm_1")
    # expect(vm).to(
    #   have_attributes(
    #     :type     => "ManageIQ::Providers::Amazon::CloudManager::Vm",
    #     :name     => "vm_1_name",
    #     :vendor   => "amazon",
    #     :location => "unknown",
    #   )
    # )
    # expect(vm.hardware).to(
    #   have_attributes(
    #     :bitness              => 64,
    #     :virtualization_type  => "hvm",
    #     :root_device_type     => "root_device_type",
    #     :cpu_sockets          => 4,
    #     :cpu_cores_per_socket => 1,
    #     :cpu_total_cores      => 6,
    #   )
    # )
    # expect(vm.availability_zone).to(
    #   have_attributes(
    #     :type    => "ManageIQ::Providers::Amazon::CloudManager::AvailabilityZone",
    #     :ems_ref => "availability_zone_1",
    #     :name    => availability_zone_name,
    #   )
    # )
    # expect(vm.flavor).to(
    #   have_attributes(
    #     :type    => "ManageIQ::Providers::Amazon::CloudManager::Flavor",
    #     :ems_ref => "flavor_1",
    #     :name    => nil,
    #   )
    # )
    # expect(vm.genealogy_parent).to(
    #   have_attributes(
    #     :type     => "ManageIQ::Providers::Amazon::CloudManager::Template",
    #     :ems_ref  => "miq_template_1",
    #     :name     => "unknown",
    #     :vendor   => "amazon",
    #     :location => "unknown",
    #   )
    # )
    # expect(vm.orchestration_stack).to(
    #   have_attributes(
    #     :type    => "ManageIQ::Providers::Amazon::CloudManager::OrchestrationStack",
    #     :ems_ref => "orchestration_stack1",
    #     :name    => nil,
    #   )
    # )

    # TODO(lsmola) the fact we have to add total_disconnected_elements means we do not reconnect deleted objects, we
    # need to fix that

    expected_all_table_counts = base_inventory_counts.merge(
      :auth_private_key    => total_elements,
      :availability_zone   => total_elements,
      :cloud_volume        => 0,
      :custom_attribute    => 0,
      :disk                => 0,
      :firewall_rule       => 0,
      :flavor              => total_elements,
      :floating_ip         => 0,
      :hardware            => total_elements + total_disconnected_elements,
      :miq_template        => total_elements + total_disconnected_elements,
      :network             => 0,
      :network_port        => 0,
      :orchestration_stack => total_elements,
      :security_group      => 0,
      :vm                  => total_elements + total_disconnected_elements,
      :vm_or_template      => (total_elements + total_disconnected_elements) * 2,
    )

    expected_ems_table_counts = expected_all_table_counts.merge(
      :auth_private_key    => total_not_deleted_elements,
      :availability_zone   => total_not_deleted_elements,
      :cloud_volume        => 0,
      :custom_attribute    => 0,
      :disk                => 0,
      :firewall_rule       => 0,
      :flavor              => total_not_deleted_elements,
      :floating_ip         => 0,
      :hardware            => total_not_deleted_elements,
      :miq_template        => total_not_deleted_elements,
      :network             => 0,
      :network_port        => 0,
      :orchestration_stack => total_not_deleted_elements,
      :security_group      => 0,
      :vm                  => total_not_deleted_elements,
      :vm_or_template      => total_not_deleted_elements * 2,
    )

    assert_table_counts(expected_all_table_counts)
    assert_ems(expected_ems_table_counts)
  end
end
