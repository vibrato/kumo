class DNA
  def self.get_node_dna(environment, file, private_ip)
    autoload :CustomDNA, file
    CustomDNA.new.dna(environment, private_ip).clean!
  rescue Exception => e
    puts "Exception while generating DNA"
    puts e.inspect
    puts e.backtrace
    raise
  end
end

# This eyesore helps to remove any null values from our DNA hash
class Hash
  def clean!
    self.delete_if do |key, val|
      if block_given?
        yield(key,val)
      else
        test1 = val.nil?
        test4 = val.empty? if val.respond_to?('empty?')
        test1 || test4
      end
    end

    self.each do |key, val|
      if self[key].is_a?(Hash) && self[key].respond_to?('clean!')
        if block_given?
          self[key] = self[key].clean!(&Proc.new)
        else
          self[key] = self[key].clean!
        end
      end

      self.delete(key) if self[key] == {}
    end

    return self
  end
end
