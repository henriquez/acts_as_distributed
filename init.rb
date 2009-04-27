
require 'acts_as_distributed'
require 'distribute'
ActiveRecord::Base.send :include, Core::Acts::Distributed


