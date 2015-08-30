class Kumo
  class Stack
    attr_reader :name

    def initialize(name, s3, cloudformation, parameters)
      @name           = name
      @s3             = s3
      @cloudformation = cloudformation
      @parameters     = parameters
    end

    # Create CloudFormation stack on AWS
    def create(template_url)
      begin
        puts "Creating stack #{@name}"

        @cloudformation.create_stack(
          stack_name: @name,
#          template_url: template_url,
          template_body: File.open("hava-dns.json").read,
          capabilities: ["CAPABILITY_IAM"],
          parameters: @parameters,
          disable_rollback: true,
          tags: [{
            key: "environment",
            value: @name
          }])

        wait_for_stack("CREATE_COMPLETE")

      rescue Exception => e
        puts e.inspect
        puts e.backtrace
      end
    end

    # Update CloudFormation stack on AWS
    def update(template_url)
      puts "Updating stack (#{@name})"

      puts @parameters

      @cloudformation.update_stack(
        stack_name: @name,
#          template_url: template_url,
        template_body: File.open("hava.json").read,
        capabilities: ["CAPABILITY_IAM"],
        parameters: @parameters)

      wait_for_stack("UPDATE_COMPLETE")

    rescue Aws::CloudFormation::Errors::ValidationError => e
      puts e.message
    rescue Exception => e
      puts e.inspect
      puts e.backtrace
    end

    # Delete CloudFormation stack on AWS
    def destroy
      begin
        puts "Deleting stack (#{@name})"

        @cloudformation.delete_stack(
          stack_name: @name)

        wait_for_stack("UPDATE_COMPLETE")

      # This will be raised once the stack successfully deletes
      rescue Aws::CloudFormation::Errors::ValidationError => e
        puts "Stack deleted"
      rescue Exception => e
        puts e.inspect
        puts e.backtrace
      end
    end

    # Parse the given template and upload to S3
    def upload_templates(templates, bucket)
      templates.each do |path|
        puts "Uploading #{path} to #{bucket}/#{path}"
        template = JSON.parse(File.open(path).read)

        @s3.put_object(
          acl:    "authenticated-read",
          body:   JSON.pretty_generate(template),
          bucket: bucket,
          key:    path)
      end
    end

    # Loop and block until CF stack reaches the desired state
    def wait_for_stack(desired_state)
      waiting = true
      while waiting do
        response = @cloudformation.describe_stacks(stack_name: name)
        stack    = response[:stacks].first

        puts "Status: #{stack.stack_status}"
        break if stack.stack_status == desired_state
        sleep 10
      end
    end

    def get_outputs
      response = @cloudformation.describe_stacks(stack_name: name)
      stack    = response[:stacks].first
      stack[:outputs]
    end
  end
end
