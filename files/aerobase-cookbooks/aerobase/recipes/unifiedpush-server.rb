#
# Copyright:: Copyright (c) 2015
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'openssl'

# Default location of install-dir is /opt/unifiedpush/. This path is set during build time.
# DO NOT change this value unless you are building your own Unifiedpush packages
install_dir = node['package']['install-dir']
ENV['PATH'] = "#{install_dir}/bin:#{install_dir}/embedded/bin:#{ENV['PATH']}"

server_dir = node['unifiedpush']['unifiedpush-server']['dir']
server_log_dir = node['unifiedpush']['unifiedpush-server']['log_directory']
server_doc_dir = node['unifiedpush']['unifiedpush-server']['documents_directory']
server_upl_dir = node['unifiedpush']['unifiedpush-server']['uploads_directory']
server_conf_dir = "#{server_dir}/standalone/configuration"
server_etc_dir = "#{server_dir}/etc"

account_helper = AccountHelper.new(node)
aerobase_user = account_helper.aerobase_user

unifiedpush_vars = node['unifiedpush']['unifiedpush-server'].to_hash
global_vars = node['unifiedpush']['global'].to_hash
all_vars = unifiedpush_vars.merge(global_vars)

# These directories do not need to be writable for unifiedpush-server
[ 
  server_dir,
  server_log_dir,
  server_doc_dir, 
  server_upl_dir,
  server_etc_dir
].each do |dir_name|
  directory dir_name do
    owner aerobase_user
    group 'root'
    mode '0775'
    recursive true
  end
end

# Always re-extract wildfly and recreate configuration.
execute 'extract_wildfly' do
  command "tar xzvf #{install_dir}/embedded/apps/wildfly/wildfly-11.0.0.Final.tar.gz --strip-components 1"
  cwd "#{server_dir}"
end

# Embeded KC server, use same properties as unifiedpush-server
if node['unifiedpush']['keycloak-server']['enable']
    node.set['unifiedpush']['keycloak-server']['server_host'] = node['unifiedpush']['unifiedpush-server']['server_host']
    node.set['unifiedpush']['keycloak-server']['server_https'] = node['unifiedpush']['unifiedpush-server']['server_https']
end

include_recipe "unifiedpush::unifiedpush-server-wildfly-conf"
include_recipe "unifiedpush::keycloak-server-wildfly-conf"

# Link logrotate gir to wildfly log dir
link "#{server_log_dir}/logs" do
  to "#{server_dir}/standalone/log"
end

template "#{server_etc_dir}/environment.properties" do
  source "unifiedpush-server-env-properties.erb"
  owner aerobase_user
  mode "0644"
  variables(all_vars)
end

template "#{server_etc_dir}/db.properties" do
  source "unifiedpush-server-db-properties.erb"
  owner aerobase_user
  mode "0644"
  variables(all_vars)
end

component_runit_service "unifiedpush-server" do
  package "unifiedpush"
end

# Make sure owner is aerobase_user
execute "chown-unifiedpush-server" do
  command "chown -R #{aerobase_user}:root #{server_dir}"
  action :run
end

if node['unifiedpush']['bootstrap']['enable']
  execute "/opt/unifiedpush/bin/unifiedpush-ctl start unifiedpush-server" do
    retries 20
  end
end
