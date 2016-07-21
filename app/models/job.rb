require 'nokogiri'
require "prawn/measurement_extensions"
require 'httparty'

class Job < ActiveRecord::Base
  default_scope {where( :deleted_at => nil )} #Hides all deleted jobs from all queries, works as long as no deleted jobs needs to be visualized in dFlow
  scope :active, -> {where(quarantined: false, deleted_at: nil)}
  Job.per_page = 50

  belongs_to :treenode
  has_many :job_activities, :dependent => :destroy
  has_many :publication_logs, :dependent => :destroy

  has_many :flow_steps, -> {where(aborted_at: nil)}, :dependent => :destroy

  validates :id, :uniqueness => true
  validates :title, :presence => true
  validates :catalog_id, :presence => true
  validates :treenode_id, :presence => true
  validates :source, :presence => true
  validates :copyright, :inclusion => {:in => [true, false]}
  validate :source_in_list
  validate :flow_in_list
  validate :xml_validity
  validates_associated :job_activities
  attr_accessor :created_by
  attr_accessor :message
  attr_accessor :nolog # Flag, set to true to inactivate job activity creation

  after_create :create_log_entry
  after_create :create_initial_flow_steps
  after_initialize :default_values

  before_validation :set_treenode_ids

  def as_json(options = {})
    if !id 
      json = {
        name: name,
        title: title
      }
    elsif options[:list]
      json = {
        id: id,
        name: name,
        title: title,
        display: display,
        source_label: source_label,
        catalog_id: catalog_id,
        breadcrumb_string: treenode_breadcrumb(as_string: true),
        treenode_id: treenode_id,
        quarantined: quarantined,
        main_status: main_status,
        is_processing: is_processing?,
        status: flow_step.description,
        comment: comment,
        object_info: object_info
      }
    else
      json = super.merge({
        display: display,
        source_label: source_label,
        breadcrumb: treenode_breadcrumb(include_self: true),
        activities: job_activities.as_json,
        metadata: metadata_hash,
        source_link: source_link,
        has_pdf: has_pdf,
        package_metadata: package_metadata_hash,
        main_status: main_status,
        files: files_list,
        is_periodical: is_periodical,
        status: flow_step.description,
        flow_step: flow_step,
        flow_steps: flow_steps,
        publication_logs: publication_logs,
        package_location: package_location,
        package_name: current_package_name
        })
    end

    return json
  end

  def treenode_breadcrumb(params)
    return nil if !treenode
    treenode.breadcrumb(params)
  end

  def set_treenode_ids
    self.parent_ids = treenode.parent_ids if treenode
    true
  end

  # Sets quarantine flag for job
  def quarantine!(msg:)
    return if self.quarantined
    self.quarantined = true
    self.save
    create_log_entry("QUARANTINE", msg)
  end

  # Unsets quarantine flag for job
  def unquarantine!(flow_step:)
    return if !self.quarantined
    self.quarantined = false
    self.current_flow_step = flow_step
    create_flow_steps(new_flow: true)
    self.save
    create_log_entry("UNQUARANTINE","_UNQUARANTINED")
  end

  # Moves job to given flow step
  def new_flow_step!(flow_step:)
    old_flow_step_string = self.flow_step.info_string
    self.current_flow_step = flow_step
    create_flow_steps
    self.save
    create_log_entry("FLOW_STEP", "Old: #{old_flow_step_string} New: #{self.flow_step.info_string}")
  end

  # Mark job as deleted
  def delete
    self.update_attribute(:deleted_at, Time.now)
  end

  # Check if job is deleted
  def deleted?
    deleted_at.present?
  end

  def default_values
    @created_by ||= 'not_set'
    @package_location ||= "PROCESSING:/#{self.id}"
  end

  # Creates a JobActivity object for CREATE event
  def create_log_entry(event="CREATE", message="_ACTIVITY_CREATED")
    entry = JobActivity.new(username: created_by, event: event, message: message)
    job_activities << entry
  end

  # Retrieve source label from config
  def source_label
    Source.find_label_by_name(source)
  end

  # Combine selected metadata into a single string to use in search_title
  def generate_search_title_metadata_string
    ord = ordinals(true)
    chron = chrons(true)
    ord_string = ord.map { |x| x.join(" ")}.compact.join(" ")
    chron_string = chron.map { |x| x.join(" ")}.compact.join(" ")
    [ord_string, chron_string].compact.join(" ")
  end

  # Generate the string to be stored in search_title
  def generate_search_title_string
    author_norm = author.blank? ? "" : author.norm
    name_norm = name.blank? ? "" : name.norm
    [
     title.norm,
     author_norm,
     name_norm,
     catalog_id.to_s,
     self.id.to_s,
     generate_search_title_metadata_string.norm
     ].compact.join(" ")
   end

  # Create search_title from title
  def build_search_title
    self.update_attribute(:search_title, generate_search_title_string)
  end

  # Generate search_titles for all jobs where it is missing
  def self.index_jobs
    Job.where(search_title: nil).each do |job|
      job.build_search_title
    end
  end

  ###VALIDATION METHODS###
  def xml_valid?(xml)
    test=Nokogiri::XML(xml)
    test.errors.empty?
  end

  # Checks validity
  def xml_validity
    errors.add(:base, "Marc must be valid xml") unless xml_valid?(xml)
  end

  # Check if source is in list of configured sources
  def source_in_list
    if !SYSTEM_DATA["sources"].map { |x| x["name"] }.include?(source)
      errors.add(:source, "not included in list of valid sources")
    end
  end

  # Check if flow is in list of configured flows
  def flow_in_list
    if !APP_CONFIG["workflows"].map { |x| x["name"] }.include?(flow)
      errors.add(:flow, "not included in list of valid sources")
    end
  end

  ########################


  # Updates metadata for a specific key
  def update_metadata_key(key, metadata)
    metadata_temp = JSON.parse(self.metadata || '{}')
    metadata_temp[key] = metadata
    self.metadata = metadata_temp.to_json
  end

  # Updates metadata for a specific key
  def update_package_metadata_key(key, metadata)
    metadata_temp = JSON.parse(self.package_metadata || '{}')
    metadata_temp[key] = metadata
    self.package_metadata = metadata_temp.to_json
  end

  # Updates flow parameters for a specific key
  def update_flow_param_key(key, param)
    flow_params_temp = JSON.parse(self.flow_params || '{}')
    flow_params_temp[key] = param
    self.flow_params = flow_params_temp
  end

  # Returns flow parameters for a spaecific key
  def get_flow_param_key(key)
    JSON.parse(self.flow_params || '{}')[key]
  end

  # Returns the source object class for job - located in ./sources/
  def source_object
    Source.find_by_name(source)
  end

  # Returns link to source if applicatble
  def source_link
    return source_object.try(:source_link, catalog_id)
  end

  # Returns a legible title string in an illegible manner
  def title_string
    (title[/^(.*)\s*\/\s*$/,1] || title).strip
  end

  # Generates a display title used in lists primarily
  def display
    title_trunc = title_string.truncate(85, separator: ' ')
    display = name.present? ? name : title_trunc
    if !ordinals.blank?
      display += " (#{ordinals})"
    else
      if !name.blank? && !title.blank?
        display += " (#{title_trunc})"
      end
    end
    display
  end

  # Returns a specific metadata value from key
  def metadata_value(key)
    metadata_hash[key.to_s]
  end

  # Returns all metadata as a hash
  def metadata_hash
    return {} if metadata.blank? || metadata == "null"
    @metadata_hash ||= JSON.parse(metadata)
  end

  # Returns all package_metadata as a hash
  def package_metadata_hash
    return {} if package_metadata.blank? || package_metadata == "null"
    @package_metadata_hash ||= JSON.parse(package_metadata)
  end

  # Returns ordinal data as a string representation
  def ordinals(return_raw = false)
    ordinal_data = []
    ordinal_data << ordinal_num(1) if ordinal_num(1)
    ordinal_data << ordinal_num(2) if ordinal_num(2)
    ordinal_data << ordinal_num(3) if ordinal_num(3)
    return ordinal_data if return_raw
    ordinal_data.map { |x| x.join(" ") }.join(", ")
  end

  # Returns an ordinal array for given key
  def ordinal_num(num)
    key = metadata_value("ordinal_#{num}_key")
    value = metadata_value("ordinal_#{num}_value")
    return nil if key.blank? || value.blank?
    [key, value]
  end

  # Returns chronological data as a string representation
  def chrons(return_raw = false)
    chron_data = []
    chron_data << chron_num(1) if chron_num(1)
    chron_data << chron_num(2) if chron_num(2)
    chron_data << chron_num(3) if chron_num(3)
    return chron_data if return_raw
    chron_data.map { |x| x.join(" ") }.join(", ")
  end

  # Returns an chronological array for given key
  def chron_num(num)
    key = metadata_value("chron_#{num}_key")
    value = metadata_value("chron_#{num}_value")
    return nil if key.blank? || value.blank?
    [key, value]
  end

  # Generates a work order pdf
  def create_pdf
    PdfHelper.create_work_order(self)
  end

  # Returns current package name, depending on package_location
  def current_package_name
    self.package_location.split('/').last
  end

  def package_name
    return sprintf(APP_CONFIG['package_name'], id)
  end

  # Returns path to pdf file
  def pdf_path
    return sprintf("pdf/%s.pdf", current_package_name)
  end

  # True if PDF can be found based on config
  def has_pdf
    return DfileApi.file_exist?(source_file: "#{package_location}/#{pdf_path}")
  end

  # Restarts job by setting status and moving files
  def restart
    create_flow_steps
    self.current_flow_step = flow_object.first_step_nr
    if DfileApi.move_to_trash(source_dir: package_location) && create_flow_steps
      create_log_entry("RESTART", message)
      save!
    end
  end

  # Returns a limited number of main statuses based on current status
  # Valid values: ["DONE", "WAITING_FOR_ACTION", "PROCESSING", "ERROR"]
  def main_status
    return "ERROR" if is_error?
    return "NOT_STARTED" if is_start?
    return "DONE" if is_done?
    return "WAITING_FOR_ACTION" if is_waiting_for_action?
    return "PROCESSING" if is_processing? || is_pending?
  end

  def is_start?
    state == "START"
  end

  def is_error?
    quarantined
  end

  def is_done?
    state == "FINISH"
  end

  def is_waiting_for_action?
    state == "ACTION"
  end

  def is_processing?
    return true if state == "WAITFOR"
    return true if state == "PROCESS" && flow_step.is_active? && flow_step.running?
    return false
  end

  def is_pending?
    state == "PROCESS" && flow_step.is_active? && flow_step.pending?
  end

  # Returns a list of all files in job package
  def files_list
    return DfileApi.list_files(source_dir: package_location)
  end

  # Returns true if job is a subset of a periodical
  def is_periodical
    return source_object.try(:is_periodical, metadata_value('type_of_record'))
  end

  def set_current_flow_step(flow_step)
    self.update_attribute('current_flow_step', flow_step.step)
    self.update_attribute('state', flow_step.main_state)
  end

  # Returns current flow step object
  def flow_step
    FlowStep.job_flow_step(job_id: id, flow_step: current_flow_step || 10)
  end

  # Run on create
  def create_initial_flow_steps
    create_flow_steps
  end

   # Creates flow_steps for flow
  def create_flow_steps(new_flow: false)
    if !Flow.find(self.flow).apply_flow(job: self, step_nr: self.current_flow_step, new_flow: new_flow)
      raise StandardError, "Could not create flow for job"
    end
    self.reload
  end

  # Changes the flow, aborts all previous flow steps and creates new ones
  def change_flow(flow_name: nil, step_nr: nil)
    if flow_name
      self.update_attribute('flow', flow_name)
    end
    if step_nr
      self.update_attribute('current_flow_step', step_nr)
    end
    create_flow_steps(new_flow: true)
    self.update_attribute('state', flow_step.main_state)
  end

  # Sets jobs to finished
  def finish_job
    self.update_attribute('current_flow_step', Flow.find(self.flow).last_step)
    self.update_attribute('state', 'FINISH')
  end

  def flow_object
    Flow.find(self.flow)
  end

  def page_count
    package_metadata_hash['image_count'] || -1
  end
end

