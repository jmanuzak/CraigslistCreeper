require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'pony'
require 'yaml'

class CraigslistCreeper
	def initialize()
		param_file_path = File.join(File.dirname(__FILE__), ARGV[0] ||= "params.yaml")
		@config = YAML.load_file(param_file_path)
	end

	def build_url(search, location)
		url = "http://" + location + '.craigslist.org/search/' + search['category'] + '?'
		url += ('query=' + search['query'] + '&') unless search['query'].nil?
		url += ('addOne=' + search['addOne'] + '&') unless search['addOne'].nil?
		url = URI::escape(url)
		url
	end

	def current_listings(url)
		doc = Nokogiri::HTML(open(url))
		posts = []
		doc.css('p').each_with_index do |link, index|
			href = link.css('a').first['href']
			posts << href
		end
		posts
	end

	def content_of(posts)
		listings = []
		posts.each do |post|
			listing = Nokogiri::HTML(open(post)) rescue nil
			listings << [post, listing.css("#userbody"), listing.css('h2')] if listing
		end
		listings
	end

	def send_mail(mail_body, to, subscription)
		Pony.mail(
			:from => 'craigslistbot@maxogden.com', 
			:subject=> "Craigslist alert for #{subscription} @ #{DateTime.now.to_s}!",
			:headers => { 'Content-Type' => 'text/html' },			
			:body => mail_body,
			:to => to,
			:via => :smtp, 
			:via_options => {
				:address              => @config['email']['host'],
				:port                 => @config['email']['port'],
				:enable_starttls_auto => true,
				:user_name            => @config['email']['user'],
				:password             => @config['email']['password'],
				:authentication       => :plain, # :plain, :login, :cram_md5, no auth by default
				:domain               => "localhost.localdomain" # the HELO domain provided by the client to the server
			}
		)
	end

	def mail(listings, subscription)
		mail_body = "<html><body>"
		listings.each do |href, listing, title|
			mail_body += "</br> #{title} </br> #{href} </br> #{listing} </hr>"
		end
		mail_body += '</body></html>'
		send_mail(mail_body, @config['to'], subscription)

	end

	def get_most_recent_post(file_name)
		file_path = File.join(File.dirname(__FILE__), file_name)
		id = nil
		if File.exists?(file_name)
			f = File.open(file_name)
			id = f.read
		end
		id
	end

	def set_most_recent_post(file_name, id)
		file_path = File.join(File.dirname(__FILE__), file_name)
		File.open(file_path, 'w') {|f| f.write(id)}
	end

	def filter_updated(posts, job_name)
		newest_href = nil
		old_index = nil
		last_href = get_most_recent_post(job_name).chomp

		posts.each_with_index do |href, index|
			if index == 0
				newest_href = href
			end
			
			if last_href == href
				old_index = index
				break
			end
		end
		
		set_most_recent_post(job_name, newest_href)

		posts = posts[0...old_index] if old_index != nil
		posts
	end

	def run
		criteria = @config['criteria']
		criteria.each do |search|
			locations = search['locations'].split(",")
			locations.each do |location|
				job_name = search['id'] + '-' + location

				url = build_url(search,location)
				posts = current_listings(url)
				posts = filter_updated(posts, job_name)
				listing_content = content_of(posts)

				mail(listing_content, job_name) unless posts.size == 0

				puts "Processed #{job_name}; Sent #{posts.size} results"
			end
		end
	end
end

CraigslistCreeper.new().run()
