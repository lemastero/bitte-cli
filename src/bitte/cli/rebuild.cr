module Bitte
  class CLI
    register_sub_command rebuild : Rebuild, description: "nixos-rebuild the targets"

    class Rebuild < Admiral::Command
      include Helpers

      define_help description: "nixos-rebuild"

      define_flag only : Array(String),
        description: "node names to include",
        default: Array(String).new

      property cluster : TerraformCluster?

      def run
        set_ssh_config

        ch = Channel(Nil).new
        ch_count = 0

        cluster.instances.each do |name, instance|
          ch_count += 1
          parallel_copy channel: ch,
            name: name,
            ip: instance.public_ip,
            flake: cluster.flake,
            flake_attr: instance.flake_attr,
            uid: instance.uid
        end

        cluster.asgs.each do |name, asg|
          log.info { "Copying closures to ASG #{name}" }

          asg.instances.each do |instance|
            ch_count += 1
            parallel_copy channel: ch,
              name: instance.name,
              ip: instance.public_ip,
              flake: cluster.flake,
              flake_attr: asg.flake_attr,
              uid: asg.uid
          end
        end

        ch_count.times do
          ch.receive
        end

        # nodes = cluster.nodes.values + cluster.asg_nodes
        #
        # if flags.only.any?
        #   nodes.select! { |node| flags.only.includes?(node.name) }
        # end
        #
        # nodes.each do |node|
        #   sh! "nix", "copy",
        #     "--substitute-on-destination",
        #     "--to", "ssh://root@#{node.public_ip}",
        #     "#{flake}#nixosConfigurations.#{node.uid}.config.system.build.toplevel"
        # end
        #
        # nodes.each do |node|
        #   spawn do
        #     begin
        #       sh! "nixos-rebuild",
        #         "--flake", "#{flake}##{node.uid}",
        #         "switch", "--target-host", "root@#{node.public_ip}"
        #     rescue ex
        #       log.error(exception: ex) { "nixos-rebuild failed" }
        #     ensure
        #       ch.send nil
        #     end
        #   end
        # end
        #
        # nodes.each do |_|
        #   ch.receive
        # end
      end

      def parallel_copy(channel, name, ip, flake, flake_attr, uid)
        logger = log.for(name)

        spawn do
          begin
            logger.info { "Copying closure to #{name} (#{ip})" }
            sh! "nix", "copy",
              "--substitute-on-destination",
              "--to", "ssh://root@#{ip}",
              "#{flake}##{flake_attr}",
              log: logger

            logger.info { "Copied closure, starting nixos-rebuild ..." }

            sh! "nixos-rebuild", "switch",
              "--target-host", "root@#{ip}",
              "--flake", "#{flake}##{uid}",
              log: logger

            logger.info { "finished." }
          rescue ex
            log.error(exception: ex) { "failed copying to #{name} (#{ip})" }
          ensure
            channel.send nil
          end
        end
      end

      def set_ssh_config
        ENV["NIX_SSHOPTS"] ||= (SSH::COMMON_ARGS + ssh_key).join(" ")
      end

      # def cluster
      #   Cluster.new(
      #     profile: parent.flags.as(CLI::Flags).profile,
      #     flake: flake,
      #     name: cluster_name,
      #     region: parent.flags.as(CLI::Flags).region
      #   )
      # end

      def cluster
        @cluster ||= TerraformCluster.load
      end

      def cluster_name
        parent.flags.as(CLI::Flags).cluster
        :wa
      end

      def flake
        parent.flags.as(CLI::Flags).flake
      end
    end
  end
end
