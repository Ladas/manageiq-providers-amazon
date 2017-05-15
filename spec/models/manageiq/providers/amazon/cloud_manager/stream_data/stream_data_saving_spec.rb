require_relative "../../aws_refresher_spec_common"
require_relative "../../aws_refresher_spec_counts"

describe ManageIQ::Providers::Amazon::CloudManager::Refresher do
  include AwsRefresherSpecCommon
  include AwsRefresherSpecCounts

  before(:each) do
    @ems = FactoryGirl.create(:ems_amazon_with_vcr_authentication)
  end

  # Test all kinds of graph refreshes, graph refresh, graph with recursive saving strategy
  [{:inventory_object_refresh => true},
   {:inventory_object_saving_strategy => :recursive, :inventory_object_refresh => true},].each do |inventory_object_settings|
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

      it "will a hardware first then a connected Vm" do
        @ems.reload

        persister = ManageIQ::Providers::Amazon::Inventory::Persister::StreamedData.new(
          @ems, @ems)

        persister.hardwares.build(
          :vm_or_template       => persister.vms.lazy_find("instance_1"),
          :bitness              => 64,
          :virtualization_type  => "hvm",
          :root_device_type     => "root_device_type",
          :cpu_sockets          => 4,
          :cpu_cores_per_socket => 1,
          :cpu_total_cores      => 6,
          :memory_mb            => 600,
          :disk_capacity        => 200,
          :guest_os             => persister.hardwares.lazy_find("image_1", :key => :guest_os),
        )

        ManagerRefresh::SaveInventory.save_inventory(
          @ems,
          ManagerRefresh::Inventory::Persister.from_json(persister.to_json).inventory_collections
        )

        vm = Vm.find_by(:ems_ref => "instance_1")
        expect(vm).to(
          have_attributes(
            :type     => "ManageIQ::Providers::Amazon::CloudManager::Vm",
            :name     => "unknown",
            :vendor   => "amazon",
            :location => "unknown",
          )
        )
        expect(vm.hardware).to(
          have_attributes(
            :bitness              => 64,
            :virtualization_type  => "hvm",
            :root_device_type     => "root_device_type",
            :cpu_sockets          => 4,
            :cpu_cores_per_socket => 1,
            :cpu_total_cores      => 6,
          )
        )
        expect(vm.availability_zone).to be_nil
        expect(vm.flavor).to be_nil
        expect(vm.genealogy_parent).to be_nil
        expect(vm.orchestration_stack).to be_nil

        assert_counts(
          :auth_private_key  => 0,
          :availability_zone => 0,
          :cloud_volume      => 0,
          :custom_attribute  => 0,
          :disk              => 0,
          :firewall_rule     => 0,
          :flavor            => 0,
          :floating_ip       => 0,
          :hardware          => 1,
          :miq_template      => 0,
          :network           => 0,
          :network_port      => 0,
          :security_group    => 0,
          :vm                => 1,
          :vm_or_template    => 1
        )

        # Save the VM for the first time, should update exiting vm and create all relations objects
        save_vm_with_relations
        assert_vm_relations

        # Save the same Vm second time, should update the same Vm and update all the relations
        save_vm_with_relations
        assert_vm_relations
      end
    end
  end

  def save_vm_with_relations
    # Save the same Vm second time, should update the same Vm and update all the relations
    persister = ManageIQ::Providers::Amazon::Inventory::Persister::StreamedData.new(
      @ems, @ems)
    persister.vms.build(
      :ems_ref             => "instance_1",
      :uid_ems             => "instance_1",
      :name                => "instance_1 name",
      :vendor              => "amazon",
      :raw_power_state     => "instance_1 status",
      :boot_time           => Time.now.utc,
      :availability_zone   => persister.availability_zones.lazy_find("az_1"),
      :flavor              => persister.flavors.lazy_find("flavor_1"),
      :genealogy_parent    => persister.miq_templates.lazy_find("image_1"),
      :key_pairs           => [persister.key_pairs.lazy_find("key_pair_1")],
      :location            => persister.networks.lazy_find("#image_1__public", :key => :hostname, :default => 'unknown'),
      :orchestration_stack => persister.orchestration_stacks.lazy_find("stack_1")
    )

    ManagerRefresh::SaveInventory.save_inventory(
      @ems,
      ManagerRefresh::Inventory::Persister.from_json(persister.to_json).inventory_collections
    )
  end

  def assert_vm_relations
    @ems.reload

    vm = Vm.find_by(:ems_ref => "instance_1")
    expect(vm).to(
      have_attributes(
        :type     => "ManageIQ::Providers::Amazon::CloudManager::Vm",
        :name     => "unknown",
        :vendor   => "amazon",
        :location => "unknown",
      )
    )
    expect(vm.hardware).to(
      have_attributes(
        :bitness              => 64,
        :virtualization_type  => "hvm",
        :root_device_type     => "root_device_type",
        :cpu_sockets          => 4,
        :cpu_cores_per_socket => 1,
        :cpu_total_cores      => 6,
      )
    )
    expect(vm.availability_zone).to(
      have_attributes(
        :type    => "ManageIQ::Providers::Amazon::CloudManager::AvailabilityZone",
        :ems_ref => "az_1",
        :name    => nil,
      )
    )
    expect(vm.flavor).to(
      have_attributes(
        :type    => "ManageIQ::Providers::Amazon::CloudManager::Flavor",
        :ems_ref => "flavor_1",
        :name    => nil,
      )
    )
    expect(vm.genealogy_parent).to(
      have_attributes(
        :type     => "ManageIQ::Providers::Amazon::CloudManager::Template",
        :ems_ref  => "image_1",
        :name     => "unknown",
        :vendor   => "amazon",
        :location => "unknown",
      )
    )
    expect(vm.orchestration_stack).to(
      have_attributes(
        :type    => "ManageIQ::Providers::Amazon::CloudManager::OrchestrationStack",
        :ems_ref => "stack_1",
        :name    => nil,
      )
    )

    assert_counts(
      :auth_private_key    => 1,
      :availability_zone   => 1,
      :cloud_volume        => 0,
      :custom_attribute    => 0,
      :disk                => 0,
      :firewall_rule       => 0,
      :flavor              => 1,
      :floating_ip         => 0,
      :hardware            => 1,
      :miq_template        => 1,
      :network             => 0,
      :network_port        => 0,
      :orchestration_stack => 1,
      :security_group      => 0,
      :vm                  => 1,
      :vm_or_template      => 2,
    )
  end
end
