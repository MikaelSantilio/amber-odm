# AmberODM
A Ruby gem that provides a simple Object Document Mapper (ODM) for Elasticsearch. It allows you to interact with Elasticsearch in a more organized and object-oriented way.

## Installation
Add this line to your application's Gemfile:

```ruby
gem 'amber_odm'
```


And then execute:

    $ bundle

Or install it yourself as:

    $ gem install amber_odm 

# Usage
Here's a quick example of how to use EmeraldODM to interact with a ElasticSearch database:

## 1. Configuring your Elasticsearch connection
```ruby
require 'amber_odm'

AmberODM.databases_settings[:dev] = {
  url: 'http://localhost:9200',
  log: true
}

```

## 2. Define your model
```ruby
require 'amber_odm'

# Define a model for the "users" index
class User < AmberODM::Document
  
  attr_accessor :name, :email, :posts, :keywords_count

  def self.index_name
    :users
  end
  
  def self.db_name
    :dev
  end
  
  def self.posts=(posts)
    @posts = posts.map { |post| Post.new(post)}
  end
  
  class Post < AmberODM::AttrInitializer
    attr_accessor :id, :title, :body, :created_at, :updated_at
    
    def created_at
      Time.parse(@created_at)
    end

    def updated_at
      Time.parse(@updated_at)
    end
    
    def keywords
      body.scan(/\w+/)
    end
  end
  
end

```

## 3. Use it
```ruby
# Find users using a query
users = User.search(
  {
    bool: {
      must: [
        {match: {name: 'John Doe'}}
      ]
    }
  }, # filter query is required
  _source: %w[name email posts keywords_count], # optional, the default is to return all fields defined in the document
  size: 10, # optional, the default is to return all documents
)

# users is an array of User objects like Array<User>
bulk_users = []
users.each do |user|
  posts = user.posts
  all_user_keywords = posts.map(&:keywords).flatten.uniq
  user.keywords_count = all_user_keywords.count
  bulk_hash = user.get_bulk_update_hash(:keywords_count) # returns a hash that can be used to update the document field ':keywords_count' in bulk

  bulk_users << bulk_hash
end

# Update the documents in bulk
User.client.bulk(body: bulk_users) unless bulk_users.empty?
```

# Advanced usage
## Pagination
```ruby
# 1. Get the first page of users
users = User.search(
  { bool: { must: [{match: {name: 'John Doe'}}] } },
  size: 10,
  sort: [{name: 'asc'}],
)

# 2. Get the last sort value
search_after = users.last&.sort

# 3. Loop through the pages
while users.any?
  users = User.search(
    { bool: { must: [{match: {name: 'John Doe'}}] } },
    size: 10,
    sort: [{name: 'asc'}],
    search_after: search_after
  )
  
  # 4. Do something with the users documents...
  puts users.map(&:name).join(', ')
  
  # 5. Update the last sort value
  search_after = users.last&.sort
end
```
## Accessing the Elasticsearch client
```ruby
User.client # returns the Elasticsearch client from 'elasticsearch-ruby' gem
```

# Contributing
Bug reports and pull requests are welcome on GitHub at https://github.com/MikaelSantilio/amber-odm/.

# License
The gem is available as open source under the terms of the MIT License.
