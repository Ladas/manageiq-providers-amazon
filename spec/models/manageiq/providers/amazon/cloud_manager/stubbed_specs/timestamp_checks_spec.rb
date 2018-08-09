require_relative "../../aws_refresher_spec_common"
require_relative "collector_test"


describe ManageIQ::Providers::Amazon::CloudManager::Refresher do
  include AwsRefresherSpecCommon

  before(:each) do
    @ems = FactoryGirl.create(:ems_amazon_with_vcr_authentication, :name => "test_ems")
  end

  [{
     :inventory_object_refresh => true,
     :inventory_collections    => {
       :saver_strategy => :concurrent_safe_batch,
       :use_ar_object  => false,
     },
   }].each do |settings|
    context "with settings #{settings}" do
      before(:each) do
        stub_refresh_settings(settings)
      end

      it "checks the full row saving timestamps" do
        vm_created_on = nil
        vm_updated_on = nil

        2.times do
          CollectorTest.refresh(
            CollectorTest.generate_batches_of_full_vm_data(
              :ems_name  => @ems.name,
              :timestamp => newest_timestamp,
            )
          )

          Vm.find_each.each do |vm|
            expected_timestamp = expected_timestamp(vm, newest_timestamp)

            expect(vm).to(
              have_attributes(
                :name            => "instance_#{expected_timestamp}",
                :timestamp       => expected_timestamp,
                :timestamps_max  => nil,
                :timestamps      => {},
                :boot_time       => expected_timestamp,
                :raw_power_state => "#{expected_timestamp} status",
                :complete        => true,
              )
            )
          end
        end

        # Expect the second+ run with same timestamp for each record doesn't change rails timestamps (the row should
        # not be updated)
        vm_current_created_on = Vm.where(:uid_ems => "1").first.created_on
        vm_current_updated_on = Vm.where(:uid_ems => "1").first.updated_on
        vm_created_on         ||= vm_current_created_on
        vm_updated_on         ||= vm_current_updated_on
        expect(vm_created_on).to eq(vm_current_created_on)
        expect(vm_updated_on).to eq(vm_current_updated_on)
      end

      it "checks the full row saving with increasing timestamps" do
        bigger_newest_timestamp = newest_timestamp

        2.times do
          CollectorTest.refresh(
            CollectorTest.generate_batches_of_full_vm_data(
              :ems_name  => @ems.name,
              :timestamp => bigger_newest_timestamp,
            )
          )

          Vm.find_each.each do |vm|
            expected_timestamp = expected_timestamp(vm, bigger_newest_timestamp)

            expect(vm).to(
              have_attributes(
                :name            => "instance_#{expected_timestamp}",
                :timestamp       => expected_timestamp,
                :timestamps_max  => nil,
                :timestamps      => {},
                :boot_time       => expected_timestamp,
                :raw_power_state => "#{expected_timestamp} status",
                :complete        => true,
              )
            )
          end

          bigger_newest_timestamp += 10.minutes
        end
      end

      it "checks the full row saving with increasing timestamps forcing upsert" do
        allow(@ems).to receive(:vms) { Vm.none }

        bigger_newest_timestamp = newest_timestamp

        2.times do
          CollectorTest.refresh(
            CollectorTest.generate_batches_of_full_vm_data(
              :ems_name  => @ems.name,
              :timestamp => bigger_newest_timestamp,
            )
          )

          Vm.find_each.each do |vm|
            expected_timestamp = expected_timestamp(vm, bigger_newest_timestamp)

            expect(vm).to(
              have_attributes(
                :name            => "instance_#{expected_timestamp}",
                :timestamp       => expected_timestamp,
                :timestamps_max  => nil,
                :timestamps      => {},
                :boot_time       => expected_timestamp,
                :raw_power_state => "#{expected_timestamp} status",
                :complete        => true,
              )
            )
          end

          bigger_newest_timestamp += 10.minutes
        end
      end

      it "checks the partial rows saving timestamps" do
        vm_created_on = nil
        vm_updated_on = nil

        2.times do
          CollectorTest.refresh(
            CollectorTest.generate_batches_of_partial_vm_data(
              :ems_name  => @ems.name,
              :timestamp => newest_timestamp,
            )
          )

          Vm.find_each do |vm|
            expected_timestamp = expected_timestamp(vm, newest_timestamp)

            expect(vm).to(
              have_attributes(
                :name            => nil,
                :timestamp       => nil,
                :timestamps_max  => expected_timestamp,
                :boot_time       => expected_timestamp,
                :raw_power_state => "#{expected_timestamp} status",
                :complete        => true, # TODO(lsmola) should be false
              )
            )

            expect(time_parse(vm.timestamps["raw_power_state"])).to eq expected_timestamp
            expect(time_parse(vm.timestamps["uid_ems"])).to eq expected_timestamp
            expect(time_parse(vm.timestamps["boot_time"])).to eq expected_timestamp
          end

          # Expect the second+ run with same timestamp for each record doesn't change rails timestamps (the row should
          # not be updated)
          vm_current_created_on = Vm.where(:uid_ems => "1").first.created_on
          vm_current_updated_on = Vm.where(:uid_ems => "1").first.updated_on
          vm_created_on         ||= vm_current_created_on
          vm_updated_on         ||= vm_current_updated_on
          expect(vm_created_on).to eq(vm_current_created_on)
          expect(vm_updated_on).to eq(vm_current_updated_on)
        end
      end

      it "check full then partial with the same timestamp" do
        vm_created_on = nil
        vm_updated_on = nil

        2.times do
          CollectorTest.refresh(
            CollectorTest.generate_batches_of_full_vm_data(
              :ems_name  => @ems.name,
              :timestamp => newest_timestamp,
            )
          )

          # Expect the second+ run with same timestamp for each record doesn't change rails timestamps (the row should
          # not be updated)
          vm_created_on = Vm.where(:uid_ems => "1").first.created_on
          vm_updated_on = Vm.where(:uid_ems => "1").first.updated_on
        end

        2.times do
          CollectorTest.refresh(
            CollectorTest.generate_batches_of_partial_vm_data(
              :ems_name  => @ems.name,
              :timestamp => newest_timestamp,
            )
          )

          Vm.find_each do |vm|
            expected_timestamp = expected_timestamp(vm, newest_timestamp)

            expect(vm).to(
              have_attributes(
                :name            => "instance_#{expected_timestamp}",
                :timestamp       => expected_timestamp,
                :timestamps_max  => nil,
                :timestamps      => {},
                :boot_time       => expected_timestamp,
                :raw_power_state => "#{expected_timestamp} status",
                :complete        => true,
              )
            )
          end

          # Expect the second+ run with same timestamp for each record doesn't change rails timestamps (the row should
          # not be updated)
          vm_current_created_on = Vm.where(:uid_ems => "1").first.created_on
          vm_current_updated_on = Vm.where(:uid_ems => "1").first.updated_on
          expect(vm_created_on).to eq(vm_current_created_on)
          expect(vm_updated_on).to eq(vm_current_updated_on)
        end
      end

      it "check partial then full with the same timestamp" do
        2.times do
          CollectorTest.refresh(
            CollectorTest.generate_batches_of_partial_vm_data(
              :ems_name  => @ems.name,
              :timestamp => newest_timestamp,
            )
          )

          Vm.find_each do |vm|
            expected_timestamp = expected_timestamp(vm, newest_timestamp)

            expect(vm).to(
              have_attributes(
                :name            => nil,
                :timestamp       => nil,
                :timestamps_max  => expected_timestamp,
                :boot_time       => expected_timestamp,
                :raw_power_state => "#{expected_timestamp} status",
                :complete        => true,
              )
            )

            expect(time_parse(vm.timestamps["raw_power_state"])).to eq expected_timestamp
            expect(time_parse(vm.timestamps["uid_ems"])).to eq expected_timestamp
            expect(time_parse(vm.timestamps["boot_time"])).to eq expected_timestamp
          end
        end

        2.times do
          CollectorTest.refresh(
            CollectorTest.generate_batches_of_full_vm_data(
              :ems_name  => @ems.name,
              :timestamp => newest_timestamp,
            )
          )

          Vm.find_each do |vm|
            expected_timestamp = expected_timestamp(vm, newest_timestamp)

            expect(vm).to(
              have_attributes(
                :name            => "instance_#{expected_timestamp}",
                :timestamp       => expected_timestamp,
                :timestamps_max  => nil,
                :timestamps      => {},
                :boot_time       => expected_timestamp,
                :raw_power_state => "#{expected_timestamp} status",
                :complete        => true,
              )
            )
          end
        end
      end

      it "check full then partial with the bigger timestamp" do
        vm_created_on = nil
        vm_updated_on = nil

        bigger_newest_timestamp = newest_timestamp + 1.second

        2.times do
          CollectorTest.refresh(
            CollectorTest.generate_batches_of_full_vm_data(
              :ems_name  => @ems.name,
              :timestamp => newest_timestamp,
            )
          )

          # Expect the second+ run with same timestamp for each record doesn't change rails timestamps (the row should
          # not be updated)
          vm_created_on = Vm.where(:uid_ems => "1").first.created_on
          vm_updated_on = Vm.where(:uid_ems => "1").first.updated_on
        end

        2.times do
          CollectorTest.refresh(
            CollectorTest.generate_batches_of_partial_vm_data(
              :ems_name  => @ems.name,
              :timestamp => bigger_newest_timestamp,
            )
          )

          Vm.find_each do |vm|
            expected_timestamp        = expected_timestamp(vm, newest_timestamp)
            expected_bigger_timestamp = expected_timestamp(vm, bigger_newest_timestamp)
            expect(vm).to(
              have_attributes(
                :name            => "instance_#{expected_timestamp}",
                :timestamp       => expected_timestamp,
                :timestamps_max  => expected_bigger_timestamp,
                :boot_time       => expected_bigger_timestamp,
                :raw_power_state => "#{expected_bigger_timestamp} status",
                :complete        => true,
              )
            )

            expect(time_parse(vm.timestamps["raw_power_state"])).to eq expected_bigger_timestamp
            expect(time_parse(vm.timestamps["uid_ems"])).to eq expected_bigger_timestamp
            expect(time_parse(vm.timestamps["boot_time"])).to eq expected_bigger_timestamp
          end

          # Expect the second+ run with same timestamp for each record doesn't change rails timestamps (the row should
          # not be updated)
          vm_current_created_on = Vm.where(:uid_ems => "1").first.created_on
          vm_current_updated_on = Vm.where(:uid_ems => "1").first.updated_on
          vm_partial_updated_on ||= vm_current_updated_on # We've updated the partial columns
          expect(vm_created_on).to eq(vm_current_created_on)
          expect(vm_partial_updated_on).to eq(vm_current_updated_on)
        end
      end

      it "check partial then full with the bigger timestamp" do
        bigger_newest_timestamp = newest_timestamp + 1.second

        2.times do
          CollectorTest.refresh(
            CollectorTest.generate_batches_of_partial_vm_data(
              :ems_name  => @ems.name,
              :timestamp => newest_timestamp,
            )
          )
        end

        2.times do
          CollectorTest.refresh(
            CollectorTest.generate_batches_of_full_vm_data(
              :ems_name  => @ems.name,
              :timestamp => bigger_newest_timestamp,
            )
          )

          Vm.find_each do |vm|
            expected_bigger_timestamp = expected_timestamp(vm, bigger_newest_timestamp)

            expect(vm).to(
              have_attributes(
                :name            => "instance_#{expected_bigger_timestamp}",
                :timestamp       => expected_bigger_timestamp,
                :timestamps_max  => nil,
                :timestamps      => {},
                :boot_time       => expected_bigger_timestamp,
                :raw_power_state => "#{expected_bigger_timestamp} status",
                :complete        => true,
              )
            )
          end
        end
      end

      it "checks that full refresh with lower timestamp running after partial, will turn to partial updates" do
        bigger_newest_timestamp      = newest_timestamp + 1.second
        even_bigger_newest_timestamp = newest_timestamp + 2.second

        2.times do
          CollectorTest.refresh(
            CollectorTest.generate_batches_of_partial_vm_data(
              :ems_name  => @ems.name,
              :timestamp => bigger_newest_timestamp,
            )
          )

          # Expect the second+ run with same timestamp for each record doesn't change rails timestamps (the row should
          # not be updated)
          vm_created_on = Vm.where(:uid_ems => "1").first.created_on
          vm_updated_on = Vm.where(:uid_ems => "1").first.updated_on
        end

        2.times do
          persister = CollectorTest.generate_batches_of_full_vm_data(
            :ems_name    => @ems.name,
            :timestamp   => newest_timestamp,
            :index_start => 0,
            :batch_size  => 2
          )

          CollectorTest.generate_batches_of_full_vm_data(
            :ems_name    => @ems.name,
            :timestamp   => even_bigger_newest_timestamp,
            :persister   => persister,
            :index_start => 1,
            :batch_size  => 2
          )

          CollectorTest.refresh(persister)

          Vm.find_each do |vm|
            expected_timestamp             = expected_timestamp(vm, newest_timestamp)
            expected_bigger_timestamp      = expected_timestamp(vm, bigger_newest_timestamp)
            expected_even_bigger_timestamp = expected_timestamp(vm, even_bigger_newest_timestamp)

            if index(vm) >= 2
              # This gets full row update
              expect(vm).to(
                have_attributes(
                  :name => "instance_#{expected_even_bigger_timestamp}",
                  # TODO(lsmola) so this means we do full by partial, so it should be 'expected_timestamp', how to do it?
                  # It should also flip complete => true
                  :timestamp       => expected_even_bigger_timestamp,
                  :timestamps_max  => nil,
                  :timestamps      => {},
                  :boot_time       => expected_even_bigger_timestamp,
                  :raw_power_state => "#{expected_even_bigger_timestamp} status",
                  :complete        => true,
                )
              )
            else
              # This gets full row, transformed to skeletal update, leading to only updating :name
              expect(vm).to(
                have_attributes(
                  :name => "instance_#{expected_timestamp}",
                  # TODO(lsmola) so this means we do full by partial, so it should be 'expected_timestamp', how to do it?
                  # It should also flip complete => true
                  :timestamp       => nil,
                  :timestamps_max  => expected_bigger_timestamp,
                  :boot_time       => expected_bigger_timestamp,
                  :raw_power_state => "#{expected_bigger_timestamp} status",
                  :complete        => true,
                )
              )

              expect(time_parse(vm.timestamps["raw_power_state"])).to eq expected_bigger_timestamp
              expect(time_parse(vm.timestamps["uid_ems"])).to eq expected_bigger_timestamp
              expect(time_parse(vm.timestamps["boot_time"])).to eq expected_bigger_timestamp
            end
          end
        end
      end

      it "checks that 2 different partial records are batched and saved correctly when starting with older" do
        bigger_newest_timestamp = newest_timestamp + 1.second

        2.times do
          persister = CollectorTest.generate_batches_of_partial_vm_data(
            :ems_name  => @ems.name,
            :timestamp => newest_timestamp,
          )

          CollectorTest.generate_batches_of_different_partial_vm_data(
            :ems_name    => @ems.name,
            :timestamp   => bigger_newest_timestamp,
            :persister   => persister,
            :index_start => 1,
            :batch_size  => 2
          )

          CollectorTest.refresh(persister)

          CollectorTest.refresh(
            CollectorTest.generate_batches_of_different_partial_vm_data(
              :ems_name    => @ems.name,
              :timestamp   => bigger_newest_timestamp,
              :index_start => 0,
              :batch_size  => 2
            )
          )

          Vm.find_each do |vm|
            expected_timestamp        = expected_timestamp(vm, newest_timestamp)
            expected_bigger_timestamp = expected_timestamp(vm, bigger_newest_timestamp)
            expect(vm).to(
              have_attributes(
                :name            => nil,
                :timestamp       => nil,
                :version         => expected_bigger_timestamp,
                :timestamps_max  => expected_bigger_timestamp,
                :boot_time       => expected_bigger_timestamp,
                :raw_power_state => "#{expected_timestamp} status",
                :complete        => true, # TODO should be false
              )
            )

            # TODO(lsmola) wrong, this should be expected_timestamp, we need to set the right timestamps on parsing time
            if index(vm) >= 2
              expect(time_parse(vm.timestamps["raw_power_state"])).to eq expected_bigger_timestamp
            else
              expect(time_parse(vm.timestamps["raw_power_state"])).to eq expected_timestamp
            end
            expect(time_parse(vm.timestamps["uid_ems"])).to eq expected_bigger_timestamp
            expect(time_parse(vm.timestamps["boot_time"])).to eq expected_bigger_timestamp
          end
        end
      end

      it "checks that 2 different partial records are batched and saved correctly when starting with newer" do
        pending("If doing partial build of the same record multiple times, we need to check timestamps per column")
        # TODO(lsmola) the asserts are not correct

        bigger_newest_timestamp = newest_timestamp + 1.second

        2.times do
          persister = CollectorTest.generate_batches_of_partial_vm_data(
            :ems_name  => @ems.name,
            :timestamp => bigger_newest_timestamp,
          )

          CollectorTest.generate_batches_of_different_partial_vm_data(
            :ems_name    => @ems.name,
            :timestamp   => newest_timestamp,
            :persister   => persister,
            :index_start => 1,
            :batch_size  => 2
          )

          CollectorTest.refresh(persister)

          Vm.find_each do |vm|
            expected_timestamp        = expected_timestamp(vm, newest_timestamp)
            expected_bigger_timestamp = expected_timestamp(vm, bigger_newest_timestamp)
            expect(vm).to(
              have_attributes(
                :name            => nil,
                :timestamp       => nil,
                :version         => expected_bigger_timestamp,
                :timestamps_max  => expected_bigger_timestamp,
                :boot_time       => expected_bigger_timestamp,
                :raw_power_state => "#{expected_timestamp} status",
                :complete        => true, # TODO should be false
              )
            )

            # TODO(lsmola) wrong, this should be expected_timestamp, we need to set the right timestamps on parsing time
            if index(vm) >= 2
              expect(time_parse(vm.timestamps["raw_power_state"])).to eq expected_bigger_timestamp
            else
              expect(time_parse(vm.timestamps["raw_power_state"])).to eq expected_timestamp
            end
            expect(time_parse(vm.timestamps["uid_ems"])).to eq expected_bigger_timestamp
            expect(time_parse(vm.timestamps["boot_time"])).to eq expected_bigger_timestamp
          end

          CollectorTest.refresh(
            CollectorTest.generate_batches_of_different_partial_vm_data(
              :ems_name    => @ems.name,
              :timestamp   => newest_timestamp,
              :index_start => 0,
              :batch_size  => 2
            )
          )

          Vm.find_each do |vm|
            expected_timestamp        = expected_timestamp(vm, newest_timestamp)
            expected_bigger_timestamp = expected_timestamp(vm, bigger_newest_timestamp)
            expect(vm).to(
              have_attributes(
                :name            => nil,
                :timestamp       => nil,
                :version         => expected_bigger_timestamp,
                :timestamps_max  => expected_bigger_timestamp,
                :boot_time       => expected_bigger_timestamp,
                :raw_power_state => "#{expected_timestamp} status",
                :complete        => true, # TODO should be false
              )
            )

            # TODO(lsmola) wrong, this should be expected_timestamp, we need to set the right timestamps on parsing time
            if index(vm) >= 2
              expect(time_parse(vm.timestamps["raw_power_state"])).to eq expected_bigger_timestamp
            else
              expect(time_parse(vm.timestamps["raw_power_state"])).to eq expected_timestamp
            end
            expect(time_parse(vm.timestamps["uid_ems"])).to eq expected_bigger_timestamp
            expect(time_parse(vm.timestamps["boot_time"])).to eq expected_bigger_timestamp
          end
        end
      end
    end
  end

  private

  def index(vm)
    vm.uid_ems.to_i
  end

  def expected_timestamp(vm, newest_timestamp)
    newest_timestamp + index(vm).minutes
  end

  def newest_timestamp
    time_parse("2018-08-07 08:12:17 UTC")
  end

  def time_parse(time)
    Time.find_zone("UTC").parse(time)
  end

end
