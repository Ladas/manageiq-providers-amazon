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
        total_elements = 11234
        ActiveRecord::Base.logger = Logger.new(STDOUT)

        # ManageIQPerformance.profile do
          _, timings = Benchmark.realtime_block(:ems_total_refresh) do
            generate_batches_od_data(:ems_name => @ems.name, :total_elements => total_elements, :batch_size => 1000)
          end
          $log.info "#{@ems.id} LADAS_TOTAL_BENCH 1st refresh #{timings.inspect}"
        # end

        # ManageIQPerformance.profile do
          _, timings = Benchmark.realtime_block(:ems_total_refresh) do
            generate_batches_od_data(:ems_name => @ems.name, :total_elements => total_elements, :batch_size => 1000)
          end
          $log.info "#{@ems.id} LADAS_TOTAL_BENCH 2nd refresh #{timings.inspect}"
        # end

        assert_counts_and_relations(total_elements)
        puts "finished"
        while true do
          sleep(1000)
        end
      end
    end
  end

  def generate_batches_od_data(ems_name:, total_elements:, batch_size: 1000)
    ems       = ExtManagementSystem.find_by(:name => ems_name)
    persister = ManageIQ::Providers::Amazon::Inventory::Persister::StreamedData.new(
      ems, ems
    )
    count     = 1

    persister, count = process_entity(ems, :vm, persister, count, total_elements, batch_size)
    persister, count = process_entity(ems, :image, persister, count, total_elements, batch_size)
    persister, count = process_entity(ems, :hardware, persister, count, total_elements, batch_size)
    persister, count = process_entity(ems, :availability_zone, persister, count, total_elements, batch_size)
    persister, count = process_entity(ems, :flavor, persister, count, total_elements, batch_size)
    persister, count = process_entity(ems, :orchestration_stack, persister, count, total_elements, batch_size)
    persister, count = process_entity(ems, :key_pair, persister, count, total_elements, batch_size)

    # Send or update the rest which is batch smaller than the batch size
    send_or_update(ems, persister, :rest, batch_size)
  end

  def process_entity(ems, entity_name, starting_persister, starting_count, total_elements, batch_size)
    persister = starting_persister
    count     = starting_count

    (1..total_elements).each do |index|
      send("parse_#{entity_name.to_s}", index, persister)
      persister, count = send_or_update(ems, persister, count, batch_size)
    end

    return persister, count
  end

  def send_or_update(ems, persister, count, batch_size)
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
      return_count     = count + 1
    end

    return return_persister, return_count
  end

  def parse_orchestration_stack(index, persister)
    parent = index > 2 ? persister.orchestration_stacks.lazy_find("stack_#{index - 1}") : nil

    persister.orchestration_stacks.build(
      :ems_ref       => "stack_#{index}",
      :name          => "stack_#{index}_name",
      :description   => "stack_#{index}_description",
      :status        => "stack_#{index}_ok",
      :status_reason => "stack_#{index}_status_reason",
      :parent        => parent
    )
  end

  def parse_vm(index, persister)
    persister.vms.build(
      :ems_ref             => "instance_#{index}",
      :uid_ems             => "instance_#{index}_uid_ems",
      :name                => "instance_#{index}_name",
      :vendor              => "amazon",
      :raw_power_state     => "instance_#{index} status",
      :boot_time           => nil, # Time.now this will cause that dta are updated in second + refresh
      :availability_zone   => persister.availability_zones.lazy_find("az_#{index}"),
      :flavor              => persister.flavors.lazy_find("flavor_#{index}"),
      :genealogy_parent    => persister.miq_templates.lazy_find("image_#{index}"),
      # :key_pairs           => [persister.key_pairs.lazy_find("key_pair_#{index}")],
      :location            => persister.networks.lazy_find("image_#{index}__public", :key => :hostname, :default => 'unknown'),
      :orchestration_stack => persister.orchestration_stacks.lazy_find("stack_#{index}")
    )
  end

  def parse_image(index, persister)
    persister.miq_templates.build(
      :ems_ref            => "image_#{index}",
      :uid_ems            => "image_#{index}_uid_ems",
      :name               => "image_#{index}_name",
      :location           => "image_#{index}_location",
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
      :ems_ref => "az_#{index}",
      :name    => "az_#{index}_name"
    )
  end

  def parse_hardware(index, persister)
    persister.hardwares.build(
      :vm_or_template       => persister.vms.lazy_find("instance_#{index}"),
      :bitness              => 64,
      :virtualization_type  => "hvm",
      :root_device_type     => "root_device_type",
      :cpu_sockets          => 4,
      :cpu_cores_per_socket => 1,
      :cpu_total_cores      => 6,
      :memory_mb            => 600,
      :disk_capacity        => 200,
      :guest_os             => persister.hardwares.lazy_find("image_#{index}", :key => :guest_os),
    )
  end

  def parse_key_pair(index, persister)
    persister.key_pairs.build(
      :name        => "key_pair_#{index}",
      :fingerprint => "key_pair_#{index}_fingerprint"
    )
  end

  def assert_counts_and_relations(total_elements)
    @ems.reload

    # vm = Vm.find_by(:ems_ref => "instance_1")
    # expect(vm).to(
    #   have_attributes(
    #     :type     => "ManageIQ::Providers::Amazon::CloudManager::Vm",
    #     :name     => "instance_1_name",
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
    #     :ems_ref => "az_1",
    #     :name    => az_name,
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
    #     :ems_ref  => "image_1",
    #     :name     => "unknown",
    #     :vendor   => "amazon",
    #     :location => "unknown",
    #   )
    # )
    # expect(vm.orchestration_stack).to(
    #   have_attributes(
    #     :type    => "ManageIQ::Providers::Amazon::CloudManager::OrchestrationStack",
    #     :ems_ref => "stack_1",
    #     :name    => nil,
    #   )
    # )

    assert_counts(
      :auth_private_key    => total_elements,
      :availability_zone   => total_elements,
      :cloud_volume        => 0,
      :custom_attribute    => 0,
      :disk                => 0,
      :firewall_rule       => 0,
      :flavor              => total_elements,
      :floating_ip         => 0,
      :hardware            => total_elements,
      :miq_template        => total_elements,
      :network             => 0,
      :network_port        => 0,
      :orchestration_stack => total_elements,
      :security_group      => 0,
      :vm                  => total_elements,
      :vm_or_template      => total_elements * 2,
    )
  end
end
