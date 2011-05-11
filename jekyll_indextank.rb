require 'rubygems'
require 'indextank'
require 'nokogiri'

module Jekyll

  class Post
    # @origin https://github.com/kinnetica/jekyll-plugins/blob/master/sitemap_generator.rb
    attr_accessor :name

    def full_path_to_source
      File.join(@base, @name)
    end

    def location_on_server
      "#{url}"
    end
  end

  class Page
    # @origin https://github.com/kinnetica/jekyll-plugins/blob/master/sitemap_generator.rb
    attr_accessor :name

    def full_path_to_source
      File.join(@base, @dir, @name)
    end

    def location_on_server
      "#{@dir}#{url}"
    end
  end

  class Indexer < Generator

    def initialize(config = {})
      super(config)
      
      raise ArgumentError.new 'Missing indextank_api_url.' unless config['indextank_api_url']
      raise ArgumentError.new 'Missing indextank_index.' unless config['indextank_index']
      
      @storage_dir = File.join(self.home_dir, '.jekyll_indextank')
      @last_indexed_file = File.join(@storage_dir, 'last_index')
      
      create_storage_dir()
      load_stored_timestamps()
      
      @excludes = config['indextank_excludes'] || []

      api = IndexTank::Client.new(config['indextank_api_url'])
      @index = api.indexes(config['indextank_index'])
    end

    # Index all pages except pages matching any value in config['indextank_excludes']
    # The main content from each page is extracted and indexed at indextank.com
    # The doc_id of each indextank document will be the absolute url to the resource without domain name 
    def generate(site)
      puts 'Indexing pages...'
    
      items = site.pages.dup.concat(site.posts)
      items = items.find_all {|i| i.output_ext == '.html' && ! @excludes.any? {|s| i.location_on_server.include?(s)}}
      items = items.map {|i| i if @last_indexed[i.location_on_server].nil? || File.mtime(i.full_path_to_source) > @last_indexed[i.location_on_server] }.reject(&:nil?)
      
      while not @index.running?
        # wait for the indextank index to get ready
        sleep 0.5
      end
      
      items.each do |item|              
        page_text = extract_text(site,item)
        
        @index.document(item.location_on_server).add({ :text => page_text})
        @last_indexed[item.location_on_server] = Time.now
        puts 'Indexed ' << item.location_on_server
      end
      
      write_last_indexed()
      puts 'Indexing done'
    end

    # render the items, parse the output and get all text inside <p> elements
    def extract_text(site, page)
      page.render({}, site.site_payload)
      doc = Nokogiri::HTML(page.output)
      paragraphs = doc.search('p').map {|e| e.text}
      page_text = paragraphs.join(" ").gsub("\r"," ").gsub("\n"," ")
    end

    def write_last_indexed
      begin
        File.open(@last_indexed_file, 'w') {|f| Marshal.dump(@last_indexed, f)}
      rescue
        puts 'WARNING: cannot write indexed timestamps file.'
      end
    end

    def load_stored_timestamps
      begin
        @last_indexed = File.open(@last_indexed_file, "rb") {|f| Marshal.load(f)}
      rescue
        @last_indexed = {}
      end
    end

    def create_storage_dir
      begin
        Dir.mkdir(@storage_dir) unless File.exists?(@storage_dir)
      rescue SystemCallError
        puts 'WARINING: cannot create directory to store index timestamps.'
      end
    end

    def home_dir
      homes = ["HOME", "HOMEPATH"]
      ENV[homes.detect {|h| ENV[h] != nil}]
    end
    
  end
  
end