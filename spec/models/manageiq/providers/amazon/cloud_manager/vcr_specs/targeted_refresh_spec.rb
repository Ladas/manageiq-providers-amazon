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
        settings.event_targeted_refresh           = true
        settings.get_private_images               = true
        settings.get_shared_images                = true
        settings.get_public_images                = false

        allow(Settings.ems_refresh).to receive(:ec2).and_return(settings)

        # The flavors are not fetched from the API, they can go in only by appliance update, so must be in place after
        # the full refresh, lets pre-create them in the DB.
        create_flavors
      end

      it "will refresh an EC2 classic VM powered on and LB full targeted refresh" do
        vm_target = ManagerRefresh::Target.new(:manager     => @ems,
                                               :association => :vms,
                                               :manager_ref => {:ems_ref => "i-680071e9"})
        lb_target = ManagerRefresh::Target.new(:manager     => @ems,
                                               :association => :load_balancers,
                                               :manager_ref => {:ems_ref => "EmsRefreshSpec-LoadBalancer"})

        2.times do # Run twice to verify that a second run with existing data does not change anything
          @ems.reload

          VCR.use_cassette(described_class.name.underscore + "_targeted/ec2_classic_vm_and_lb_full_refresh") do
            EmsRefresh.refresh([vm_target, lb_target])
          end
          @ems.reload

          assert_specific_flavor
          assert_specific_key_pair
          assert_specific_az
          assert_specific_security_group
          assert_specific_template
          assert_specific_load_balancer_non_vpc
          assert_specific_load_balancer_non_vpc_vms
          assert_specific_vm_powered_on

          expected_counts = {
            :auth_private_key              => 1,
            :availability_zone             => 1,
            :cloud_network                 => 0,
            :cloud_subnet                  => 0,
            :cloud_volume                  => 1,
            :cloud_volume_backup           => 0,
            :cloud_volume_snapshot         => 0,
            :custom_attribute              => 2,
            :disk                          => 1,
            :ext_management_system         => 4,
            :firewall_rule                 => 13,
            :flavor                        => 2,
            :floating_ip                   => 1,
            :guest_device                  => 0,
            :hardware                      => 2,
            :miq_template                  => 1,
            :network                       => 2,
            :network_port                  => 1,
            :network_router                => 0,
            :operating_system              => 0,
            :orchestration_stack           => 0,
            :orchestration_stack_output    => 0,
            :orchestration_stack_parameter => 0,
            :orchestration_stack_resource  => 0,
            :orchestration_template        => 0,
            :security_group                => 2,
            :snapshot                      => 0,
            :system_service                => 0,
            :vm                            => 1,
            :vm_or_template                => 2
          }

          assert_counts(expected_counts)
        end
      end

      it "will refresh a VPC VM with floating IP and connected LBs" do
        vm_target   = ManagerRefresh::Target.new(:manager_id  => @ems.id,
                                                 :association => :vms,
                                                 :manager_ref => {:ems_ref => "i-8b5739f2"})
        lb_target_1 = ManagerRefresh::Target.new(:manager_id  => @ems.id,
                                                 :association => :load_balancers,
                                                 :manager_ref => {:ems_ref => "EmSRefreshSpecVPCELB"})
        lb_target_2 = ManagerRefresh::Target.new(:manager_id  => @ems.id,
                                                 :association => :load_balancers,
                                                 :manager_ref => {:ems_ref => "EmSRefreshSpecVPCELB2"})

        2.times do # Run twice to verify that a second run with existing data does not change anything
          @ems.reload

          VCR.use_cassette(described_class.name.underscore + "_targeted/vpc_vm_with_floating_ip_and_lbs_full_refresh") do
            EmsRefresh.refresh([vm_target, lb_target_1, lb_target_2])
          end
          @ems.reload

          assert_specific_flavor
          assert_specific_key_pair
          assert_specific_az
          assert_specific_security_group_on_cloud_network
          assert_specific_template
          assert_specific_load_balancer_vpc
          assert_specific_load_balancer_vpc2
          assert_specific_load_balancer_listeners_vpc_and_vpc_2
          assert_specific_cloud_volume_vm_on_cloud_network
          assert_specific_vm_on_cloud_network

          expected_counts = {
            :auth_private_key              => 1,
            :availability_zone             => 1,
            :cloud_network                 => 0,
            :cloud_subnet                  => 0,
            :cloud_volume                  => 2,
            :cloud_volume_backup           => 0,
            :cloud_volume_snapshot         => 0,
            :custom_attribute              => 2,
            :disk                          => 2,
            :ext_management_system         => 4,
            :firewall_rule                 => 3,
            :flavor                        => 2,
            :floating_ip                   => 1,
            :guest_device                  => 0,
            :hardware                      => 2,
            :miq_template                  => 1,
            :network                       => 2,
            :network_port                  => 1,
            :network_router                => 0,
            :operating_system              => 0,
            :orchestration_stack           => 0,
            :orchestration_stack_output    => 0,
            :orchestration_stack_parameter => 0,
            :orchestration_stack_resource  => 0,
            :orchestration_template        => 0,
            :security_group                => 1,
            :snapshot                      => 0,
            :system_service                => 0,
            :vm                            => 1,
            :vm_or_template                => 2
          }

          assert_counts(expected_counts)
        end
      end

      it "will refresh a VPC VM with public IP" do
        vm_target = ManagerRefresh::Target.new(:manager_id  => @ems.id,
                                               :association => :vms,
                                               :manager_ref => {:ems_ref => "i-c72af2f6"})

        2.times do # Run twice to verify that a second run with existing data does not change anything
          @ems.reload

          VCR.use_cassette(described_class.name.underscore + "_targeted/vpc_vm_with_public_ip_and_template") do
            EmsRefresh.refresh([vm_target])
          end
          @ems.reload

          assert_specific_flavor
          assert_specific_key_pair
          assert_specific_az
          assert_specific_security_group_on_cloud_network
          assert_specific_template_2
          assert_specific_cloud_volume_vm_on_cloud_network_public_ip
          assert_specific_vm_on_cloud_network_public_ip

          expected_counts = {
            :auth_private_key              => 1,
            :availability_zone             => 1,
            :cloud_network                 => 0,
            :cloud_subnet                  => 0,
            :cloud_volume                  => 2,
            :cloud_volume_backup           => 0,
            :cloud_volume_snapshot         => 0,
            :custom_attribute              => 2,
            :disk                          => 2,
            :ext_management_system         => 4,
            :firewall_rule                 => 3,
            :flavor                        => 2,
            :floating_ip                   => 1,
            :guest_device                  => 0,
            :hardware                      => 2,
            :miq_template                  => 1,
            :network                       => 2,
            :network_port                  => 1,
            :network_router                => 0,
            :operating_system              => 0,
            :orchestration_stack           => 0,
            :orchestration_stack_output    => 0,
            :orchestration_stack_parameter => 0,
            :orchestration_stack_resource  => 0,
            :orchestration_template        => 0,
            :security_group                => 1,
            :snapshot                      => 0,
            :system_service                => 0,
            :vm                            => 1,
            :vm_or_template                => 2
          }

          assert_counts(expected_counts)
        end
      end
    end
  end

  def create_flavors
    FactoryGirl.create(:flavor_amazon,
                       :ext_management_system    => @ems,
                       :name                     => "t1.micro",
                       :ems_ref                  => "t1.micro",
                       :description              => "T1 Micro",
                       :enabled                  => true,
                       :cpus                     => 1,
                       :cpu_cores                => 1,
                       :memory                   => 0.613.gigabytes.to_i,
                       :supports_32_bit          => true,
                       :supports_64_bit          => true,
                       :supports_hvm             => false,
                       :supports_paravirtual     => true,
                       :block_storage_based_only => true,
                       :ephemeral_disk_size      => 0,
                       :ephemeral_disk_count     => 0)

    FactoryGirl.create(:flavor_amazon,
                       :ext_management_system    => @ems,
                       :name                     => "t2.micro",
                       :ems_ref                  => "t2.micro",
                       :description              => "T2 Micro",
                       :enabled                  => true,
                       :cpus                     => 1,
                       :cpu_cores                => 1,
                       :memory                   => 1.0.gigabytes.to_i,
                       :supports_32_bit          => true,
                       :supports_64_bit          => true,
                       :supports_hvm             => false,
                       :supports_paravirtual     => true,
                       :block_storage_based_only => true,
                       :ephemeral_disk_size      => 0,
                       :ephemeral_disk_count     => 0)
  end
end
