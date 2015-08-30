#require "kumo/aws"
require "kumo/stack"
require "kumo/dna"
require "kumo/key"

class Environment
  attr_reader :name, :key, :type

  def initialize(name=nil, type=nil) #, template=nil)
    @name = name ? name : "development"
    @type = type ? type : "dev"
    @ssh_setup = false

    puts "Environment: #{@name}, type: #{@type}"

    # # raise 'Name is too long max 11 chars' if name.size > 11
    # #@branch          = branch
    # @template_name   = "#{template}-cf-#{Time.now.utc.iso8601.gsub(/\W/, '')}.json"
    # @template_url    = "https://s3.amazonaws.com/yarris-system/#{@template_name}"
    # @private_bucket  = "yarris-system"
    # @template_bucket = "yarris-system"
    # @snapshot        = "none"
  end

  def bootstrap
    create_s3_bucket
#    create_sns_topics
#    create_key_pair
  end

  def key_pair_exists?(name)
    ec2.describe_key_pairs(key_names: [name])
    true
  rescue Aws::EC2::Errors::InvalidKeyPairNotFound
    false
  end

  def create_stack(templates, parameters, template)
    create_or_load_key(name)
    stack = Kumo::Stack.new(name, s3, cloudformation, stackify_parameters(parameters))
    #stack.upload_templates(templates, bucket_name)
    stack.create(stack_url(template))
  end

  def update_stack(templates, parameters, template)
    create_or_load_key(name)
    stack = Kumo::Stack.new(name, s3, cloudformation, stackify_parameters(parameters))
    #stack.upload_templates(templates, bucket_name)
    stack.update(stack_url(template))
  end

  def stackify_parameters(parameters)
    parameters.collect do |k, v|
      {
        parameter_key:   k,
        parameter_value: v
      }
    end
  end

  def get_outputs(templates, parameters, template)
    create_or_load_key(name)
    stack = Kumo::Stack.new(name, s3, cloudformation, stackify_parameters(parameters))
    stack.get_outputs
  end

  def destroy_stack(parameters)
    stack = Kumo::Stack.new(name, s3, cloudformation, parameters)
    stack.destroy
  end

  def stack_url(template_name)
    "https://s3.amazonaws.com/#{bucket_name}/#{template_name}"
  end

  def cloudformation
    Aws::CloudFormation::Client.new(
      region:      region,
      credentials: aws_credentials)
  end

  def s3
    Aws::S3::Client.new(
      region:      region,
      credentials: s3_credentials)
  end

  def ec2
    Aws::EC2::Client.new(
      region:      region,
      credentials: aws_credentials)
  end

  def rds
    Aws::RDS::Client.new(
      region:      region,
      credentials: aws_credentials)
  end

  def iam
    Aws::IAM::Client.new(
      region:      region,
      credentials: aws_credentials)
  end

  def elasticache
    Aws::ElastiCache::Client.new(
      region:      region,
      credentials: aws_credentials)
  end

  def aws_credentials
    ensure_aws_credentials
    Aws::Credentials.new(@aws_access_key, @aws_secret_key)
  end

  def s3_credentials
    ensure_aws_credentials
    Aws::Credentials.new(@aws_access_key, @aws_secret_key)
  end

  def region
    "us-west-1"
  end

  def ensure_aws_credentials
    raise "Please set AWS credentials" unless (@aws_access_key && @aws_secret_key)
  end

  def get_stack(name)
    resp = cloudformation.describe_stacks(stack_name: name)
    resp[:stacks].first if resp[:stacks].any?
  end

  def create_s3_bucket
    ensure_aws_credentials
    begin
      puts "Creating S3 bucket #{bucket_name}"
      s3.create_bucket(
        acl:    "private",
        bucket: bucket_name)
    rescue Aws::S3::Errors::BucketAlreadyOwnedByYou
      puts "Bucket already created"
    end
  end

  def bucket_name
    "#{@name}-#{@type}"
  end

  def upload_scripts
    Dir.glob("scripts/**").each do |file_path|
      puts "Write #{file_path} to #{@private_bucket}"
      s3.put_object(
        acl: "authenticated-read",
        body: File.open(file_path),
        bucket: @private_bucket,
        key: file_path)
    end
  end

  def credentials(aws_access_key, aws_secret_key)
    @aws_access_key = aws_access_key
    @aws_secret_key = aws_secret_key
  end

  def setup_ssh
    return if @ssh_setup
    if @type != "dev"
      @key = create_or_load_key(name)
      @key.add_key_to_agent(name)
      set_ssh_proxy
    end
    @ssh_setup = true
  end

  def create_or_load_key(name)
    @key = Key.new

    if key_pair_exists?(name)
      puts "Key pair already exists on AWS"
      load_key(name)
    else
      puts "Key pair doesn't exist on AWS"
      create_key(name)
    end

    @key
  end

  def load_key(name)
    puts "Loading SSH Key"
    key_file = "keys/#{name}.pem"
    key_file_exists = File.exist?(key_file)

    if key_file_exists
      puts "Found existing SSH key"
      #@key = key_file
    else
      raise Exception.new("Environment's keypair already exists, please add environments key to keys/ directory")
    end
  end

  def create_key(name)
    puts "Creating SSH Key"
    key_file = "keys/#{name}.pem"
    key_file_exists = File.exist?(key_file)

    @key = Key.new
    k = nil

    if key_file_exists
      puts "Local key found"
      k = @key.load_key(name)
    else
      puts "Creating local key"
      k = @key.create_key(name)
    end

    puts "Uploading key to AWS"
    ec2.import_key_pair(key_name: name, public_key_material: k)
  end

  def on(role, &blk)
    nodes = get_instances(role: role, username: "ec2-user")
    setup_ssh
    SSHKit::DSL.on(nodes, {}, &blk)
  rescue Exception => e
    puts e.inspect
    puts e.backtrace
  end

  def dev?
    type == "dev"
  end

  def get(value, default)
    default
  end

  # Ensure all apps/<app>/chef/data_bags/certs_* are uploaded for use in AWS. Refer to top-level data_bag_from_dir.sh utility or ask nhope
  def certificate_upload(chef_dir)
#    chef_dir = "apps/#{app}/chef"
    Dir.glob("#{chef_dir}/data_bags/cert_*/") do |certdir|
      pn = Pathname.new(certdir)
      certname = pn.basename.to_s
      puts "Investigating certificate: " + certname
      begin
        resp = iam.get_server_certificate(server_certificate_name: certname)
        server_certificate = resp[:server_certificate][:server_certificate_metadata]
        puts "Deleting cert with existing ARN: " + server_certificate.arn
        iam.delete_server_certificate(server_certificate_name: certname)
        rescue Aws::IAM::Errors::NoSuchEntity
          puts "No existing cert"
      end
      secret_file = "#{chef_dir}/encrypted_data_bag_secret"
      if ! File::exist?(secret_file) then
        raise "Missing secret file: \"#{secret_file}\""
      end

      value_map = {};
      for field in [ "certificate", "private_key", "certificate_chain" ]
        # Step through the items in the data bag and decrypt them
        json_str = `knife solo data bag show #{certname} #{field} -F json --data-bag-path #{chef_dir}/data_bags --secret-file #{secret_file} -c #{chef_dir}/solo.rb`
        json = JSON.parse(json_str)
        value_map[field] = json["value"]
      end

      resp = iam.upload_server_certificate(
        server_certificate_name: certname,
        certificate_body: value_map["certificate"],
        private_key: value_map["private_key"],
        certificate_chain: value_map["certificate_chain"])

      arn = resp[:server_certificate_metadata].arn
      puts "Uploaded new certificate with ARN: " + arn + " from #{chef_dir}/data_bags/#{certname}/"
    end
  end


  # Get NAT instance details
  # FIXME: need to deal with non-natted environments
  def get_nat_ip
    puts "Getting NAT address"

    # Get first instance with "nat" role
    instance = instances_for_role("nat").first[:instances].first
    # Grab the interface that has source_dest_check set to false (most likely interface)
    primary  = instance[:network_interfaces].select { |x| x[:source_dest_check] == false }.first
    nat      = "ec2-user@#{primary[:association][:public_ip]}"

    puts " - #{nat}"
    nat
  end

  # Get App server details
  def get_instances(role: nil, username: nil, bastion: nil)
    puts "Getting instances for role: #{role}"
    servers = []
    instances_for_role(role).each do |res|
      res[:instances].each do |inst|
        servers << "#{username}@#{inst[:private_ip_address]}"
      end
    end

    puts " - #{servers.join(', ')}"
    servers
  end

  def set_ssh_proxy
    ip = get_nat_ip

    puts " Setting ssh proxy: ssh #{ip} -W %h:%p -oStrictHostKeyChecking=no"
    SSHKit::Backend::Netssh.configure do |ssh|
      ssh.ssh_options.merge!({ proxy: Net::SSH::Proxy::Command.new("ssh #{ip} -W %h:%p -oStrictHostKeyChecking=no") })
    end
  end

  def get_db(db_instance_identifier)
    resp = rds.describe_db_instances(db_instance_identifier: db_instance_identifier)
    db = resp[:db_instances].first
    raise "Transaction DB endpoint details not available yet" if db[:endpoint].nil?
    db
  end

  def get_cache(cache_cluster_id)
    resp = elasticache.describe_cache_clusters(cache_cluster_id: cache_cluster_id, show_cache_node_info: true)
    cache = resp[:cache_clusters].first
    cache_node = cache[:cache_nodes].first
    raise "Cache endpoint details not available yet" if cache_node[:endpoint].nil?
    cache_node[:endpoint][:address]
  end

  # Returns an array of EC2 reservations based on the given filter name/value and state
  def instances_for_filter(filter_name, filter_value, state = "running")
    ec2.describe_instances(
      filters: [
        { name: filter_name, values: [filter_value] },
        { name: "tag:environment", values: [name] },
        { name: "instance-state-name", values: [state] }
      ])[:reservations]
  end

  # Returns an array of EC2 reservations based on the given role and state
  def instances_for_role(role, state = "running")
    instances_for_filter("tag:role", role, state)
  end

  def upload_dna(servers, path)
    environment = self
    on servers do |server|
      dna = DNA.get_node_dna(environment, path, server.hostname)
      upload! StringIO.new(dna.to_json), "/var/tmp/dna.json"
    end
  end

  def install_git(servers)
    on servers do |server|
      as "root" do
        if test("[ ! -f '/usr/bin/git' ]")
          execute(:yum, "-y", :install, "git")
        else
          info "Git already installed on #{host}!"
        end
      end
    end
  end

  def checkout_repo(servers, repo)
    on servers do |server|
      within "/var/tmp" do
        if test("[ ! -d '/var/tmp/#{repo}' ]")
          capture(:git, :clone, "https://yarrisci:SharkYarris2013@bitbucket.org/yarris/#{repo}.git")
        else
          info "Repo already checked out on #{host}!"
        end
      end
    end
  end

  def update_repo(servers, repo, branch)
    on servers do |server|
      within "/var/tmp/#{repo}" do
        capture(:git, :fetch, "-q")
        capture(:git, :reset, "--hard", "origin/#{branch}")
        capture(:git, :checkout, "-qf", "#{branch}")
      end
    end
  end

  def install_chef(servers)
    on servers do |server|
      as "root" do
        within "/var/tmp" do

          # Download chef if it needs downloading
          if test("[ ! -f '/var/tmp/install.sh' ]")
            capture :curl, "-O", "https://www.chef.io/chef/install.sh"
            capture :chmod, "+x", "install.sh"
          else
            info "Chef already downloaded on #{host}!"
          end

          # Install chef if it needs installing
          if test("[ ! -f '/usr/bin/chef-solo' ]")
            capture :"./install.sh"
          else
            info "Chef already installed on #{host}!"
          end
        end
      end
    end
  end

  def prepare_servers(servers, path, repo, branch)
    upload_dna(servers, path)
    install_git(servers)
    checkout_repo(servers, repo)
    update_repo(servers, repo, branch)
    install_chef(servers)
  end

  def update_chef(servers, branch)
    update_repo(servers, branch)
  end
end
