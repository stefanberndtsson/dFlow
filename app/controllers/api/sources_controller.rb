
class Api::SourcesController < Api::ApiController
	before_filter :check_key

	def index
		#@response = {}
		@response[:sources] = Rails.application.config.sources
		render_json
	rescue
		error_msg(ErrorCodes::OBJECT_ERROR, "Other error occurred while retrieving sources list")
		render_json
	end

	# Validates a list of objects with sources, and returns the validated data with a list of unique catalog_ids
	# valid format is {objects: [{source_name: "String", catalog_id: int, <extra object parameters to be validated>}]}
	def validate_new_objects
		objects = params[:objects]
		if objects.empty?
			error_msg(ErrorCodes::REQUEST_ERROR, "No valid objects are given")
			render_json
			return
		end
		success = 0
		fail = 0
		catalog_ids = []
		objects.each do |object|

			# Validate source name
			source_object = Source.find_by_class_name(object[:source_name])
			if !source_object
				error_msg(ErrorCodes::OBJECT_ERROR, "Could not find a source with name '#{object[:source_name]}")
				fail += 1
				next
			end

			# Validate other parameters
			if !source_object.validate_job_fields(object)
				error_msg(ErrorCodes::VALIDATION_ERROR, "Could not validate given fields")
				fail += 1
				next
			end

			# If catalog_id is new, store it
			catalog_id = object[:catalog_id]
			if !catalog_ids.include? catalog_id
				catalog_ids << catalog_id
			end

			object[:source_id] = source_object.id
			success += 1
		end
		@response[:data] = {}
		@response[:data][:objects] = objects
		@response[:data][:catalog_ids] = catalog_ids
		if fail > 0
			error_msg(ErrorCodes::OBJECT_ERROR, "A number of objects did not validate: #{fail} / #{success+fail}")
		end

		render_json
	end

	# Renders JSON with source data for an item with the given catalog_id from a source with the given source_name.
	def fetch_source_data
		catalog_id = params[:id]
		source_name = params[:name]

		# Identify source object
		source_object = Source.find_by_name(source_name)

		if !source_object
			error_msg(ErrorCodes::OBJECT_ERROR, "Could not find a source with name #{source_name}")
			render_json
			return
		end

		# Fetch source data
		source_data = source_object.fetch_source_data(catalog_id)
		if source_data && !source_data.empty?
			@response[:data] = source_data
		else
			error_msg(ErrorCodes::OBJECT_ERROR, "Could not find source data for source: #{source_name} and catalog_id: #{catalog_id}")
		end
		render_json
	end

end
