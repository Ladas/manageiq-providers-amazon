class CollectorTest
  class << self
    def generate_batches_of_partial_vm_data(ems_name:, timestamp:, batch_size: 4, index_start: 0, persister: nil)
      ems       = ExtManagementSystem.find_by(:name => ems_name)
      persister ||= new_persister(ems)

      (index_start * batch_size..((index_start + 1) * batch_size - 1)).each do |index|
        parse_partial_vm(index, persister, timestamp + index.minutes)
      end

      persister
    end

    def generate_batches_of_different_partial_vm_data(ems_name:, timestamp:, batch_size: 4, index_start: 0, persister: nil)
      ems       = ExtManagementSystem.find_by(:name => ems_name)
      persister ||= new_persister(ems)

      (index_start * batch_size..((index_start + 1) * batch_size - 1)).each do |index|
        parse_another_partial_vm(index, persister, timestamp + index.minutes)
      end

      persister
    end

    def generate_batches_of_full_vm_data(ems_name:, timestamp:, batch_size: 4, index_start: 0, persister: nil)
      ems       = ExtManagementSystem.find_by(:name => ems_name)
      persister ||= new_persister(ems)

      (index_start * batch_size..((index_start + 1) * batch_size - 1)).each do |index|
        parse_vm(index, persister, timestamp + index.minutes)
      end

      persister
    end

    def parse_another_partial_vm(index, persister, partial_newest)
      persister.vms.build_partial(
        :ems_ref   => "instance_#{index}",
        :timestamp => partial_newest,
        :boot_time => partial_newest,
        :version   => partial_newest,
        :uid_ems   => "#{index}",
      )
    end

    def parse_partial_vm(index, persister, partial_newest)
      persister.vms.build_partial(
        :ems_ref         => "instance_#{index}",
        :raw_power_state => "#{partial_newest} status",
        :timestamp       => partial_newest,
        :boot_time       => partial_newest,
        :uid_ems         => "#{index}",
      )
    end

    def parse_vm(index, persister, timestamp)
      lazy_vm = persister.vms.lazy_find("instance_#{index}")

      persister.vms.build(
        :ems_ref             => "instance_#{index}",
        :uid_ems             => "#{index}",
        :name                => "instance_#{timestamp}",
        :vendor              => "amazon",
        :raw_power_state     => "#{timestamp} status",
        :timestamp           => timestamp,
        :boot_time           => timestamp,
        :version             => timestamp,
        :availability_zone   => persister.availability_zones.lazy_find("az_#{index}"),
        :flavor              => persister.flavors.lazy_find("flavor_#{index}"),
        :genealogy_parent    => persister.miq_templates.lazy_find("image_#{index}"),
        :location            => persister.networks.lazy_find({
                                                               :hardware    => persister.hardwares.lazy_find(:vm_or_template => lazy_vm),
                                                               :description => "public"
                                                             },
                                                             {
                                                               :key     => :hostname,
                                                               :default => 'unknown'
                                                             }),
        :orchestration_stack => persister.orchestration_stacks.lazy_find("stack_#{index}"),
      # :key_pairs           => [persister.key_pairs.lazy_find("key_pair_#{index}")],
      )

      parse_hardware(index, persister, timestamp)
    end

    def parse_hardware(index, persister, timestamp)
      persister.hardwares.build(
        :vm_or_template       => persister.vms.lazy_find("instance_#{index}"),
        :bitness              => 64,
        :virtualization_type  => "hvm",
        :root_device_type     => "root_device_type",
        :cpu_sockets          => 4,
        :timestamp            => timestamp,
        :cpu_cores_per_socket => 1,
        :cpu_total_cores      => 6,
        :memory_mb            => 600,
        :disk_capacity        => 200,
        :manufacturer         => "hardware_#{index}",
        :guest_os             => persister.hardwares.lazy_find(persister.miq_templates.lazy_find("image_#{index}"), :key => :guest_os),
      )

      parse_disks(index, persister, timestamp)
    end

    def parse_disks(index, persister, timestamp)
      persister.disks.build(
        :hardware        => persister.hardwares.lazy_find(persister.vms.lazy_find("instance_#{index}")),
        :device_name     => 'sda',
        :device_type     => "disk",
        :controller_type => "amazon",
        :location        => "dev/sda1_#{index}_1",
        :timestamp       => timestamp,
      )

      persister.disks.build(
        :hardware        => persister.hardwares.lazy_find(persister.vms.lazy_find("instance_#{index}")),
        :device_name     => 'sda1',
        :device_type     => "disk",
        :controller_type => "amazon",
        :location        => "dev/sda2_#{index}_2",
        :timestamp       => timestamp,
      )
    end

    def refresh(persister)
      # RefreshQueue.enqueue!(persister)
      #
      # desc         = persister.collections.values.map { |x| "#{x.try(:name)}: #{x.try(:data).try(:size)}" if (x.try(:data).try(:size) || 0) > 0 }.compact
      # partial_desc = persister.collections.values.map { |x| "#{x.try(:name)}: #{x.try(:skeletal_primary_index).try(:index_data).try(:size)}" if (x.try(:skeletal_primary_index).try(:index_data).try(:size) || 0) > 0 }.compact
      # start        = Time.now.utc
      #
      # sizes = []
      # sizes << "full: #{desc}" unless desc.blank?
      # sizes << "partial: #{partial_desc}" unless partial_desc.blank?
      # full_desc = "ENQUEUED: #{sizes.join(", ")}"
      #
      # puts "#{start} #{full_desc}"

      persister.class.from_json(persister.to_json).persist!
    end

    def new_persister(ems)
      ManageIQ::Providers::Amazon::Inventory::Persister::TargetCollection.new(ems, ems)
    end
  end
end
