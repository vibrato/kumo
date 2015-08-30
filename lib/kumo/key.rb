class Key
  def add_key_to_agent(key_name)
  	key_file = "keys/#{key_name}.pem"
    File.chmod(0600, key_file)
    puts `ssh-add #{key_file}`
  end

  def create_key(key_name)
    puts " Creating a new SSH key"

    key_file = "keys/#{key_name}.pem"
    key = SSHKey.generate(type: "RSA", bits: 2048)
    private_key = key.private_key

    File.open(key_file, "w") do |f|
      f.write(private_key)
    end
    File.chmod(0600, key_file)

    key.ssh_public_key
  end

  def load_key(key_name)
    puts " Loading SSH key"

    key_file = "keys/#{key_name}.pem"
    private_key = File.open(key_file).read
    key = SSHKey.new(private_key)

    key.ssh_public_key
  end
end
