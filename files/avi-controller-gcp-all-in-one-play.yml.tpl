---
- name: Avi Controller Configuration
  hosts: localhost
  connection: local
  gather_facts: no
  roles:
    - role: avinetworks.avisdk
  vars:
    avi_credentials:
        controller: "{{ controller_ip[0] }}"
        username: "{{ username }}"
        password: "{{ password }}"
        api_version: "{{ api_version }}"
    username: "admin"
    password: "{{ password }}"
    api_version: ${avi_version}
    cloud_name: "Default-Cloud"
    controller_ip:
      ${ indent(6, yamlencode(controller_ip))}
    controller_names:
      ${ indent(6, yamlencode(controller_names))}
    dns_search_domain: ${dns_search_domain}
    ansible_become: yes
    ansible_become_password: "{{ password }}"
    vpc_network_name: ${se_vpc_network_name}
    vpc_subnet_name: ${se_mgmt_subnet_name}
    vpc_project_id: ${vpc_project_id}
    region: ${region}
    se_project_id: ${se_project_id}
    gcs_project_id: ${gcs_project_id}
    name_prefix: ${name_prefix}
    se_size:
      cpu: ${se_size[0]}
      memory: ${se_size[1]}
      disk: ${se_size[2]}
    se_ha_mode: ${se_ha_mode}
    vip_allocation_strategy: ${vip_allocation_strategy}
    controller_ha: ${controller_ha}
%{ if se_service_account != null ~}
    gcp_service_account_email: ${se_service_account}
%{ endif ~}
%{ if dns_servers != null ~}
    dns_servers:
%{ for item in dns_servers ~}
      - addr: "${item}"
        type: "V4"
%{ endfor ~}
%{ endif ~}
    ntp_servers:
%{ for item in ntp_servers ~}
      - server:
          addr: "${item.addr}"
          type: "${item.type}"
%{ endfor ~}
    configure_ipam_profile: ${configure_ipam_profile}
    ipam_networks:
%{ if configure_ipam_profile ~}
      ${ indent(6, yamlencode(ipam_networks))}
%{ else ~}
      - "network": "{{ ipam_network_1 | default('192.168.251.0/24') }}"
        "static_pool":
        - "{{ ipam_network_1_start | default('192.168.251.10') }}"
        - "{{ ipam_network_1_end | default('192.168.251.254') }}"
%{ endif ~}
    configure_dns_profile: ${configure_dns_profile}
%{ if configure_dns_profile ~}
    dns_domain: "{{ dns_service_domain | default('${dns_service_domain}') }}"
%{ else ~}
    dns_domain: "{{ dns_service_domain | default(omit) }}"
%{ endif ~}
    configure_dns_vs: ${configure_dns_vs}
%{ if configure_dns_vs ~}
    dns_vs_settings: 
      ${ indent(6, yamlencode(dns_vs_settings))}
%{ endif ~}
    configure_gslb: ${configure_gslb}
    create_gslb_se_group: ${create_gslb_se_group}
    gslb_user: "gslb-admin"
    gslb_se_size:
      cpu: ${gslb_se_size[0]}
      memory: ${gslb_se_size[1]}
      disk: ${gslb_se_size[2]}
    gslb_site_name: ${gslb_site_name}
    configure_gslb_additional_sites: ${configure_gslb_additional_sites}
    additional_gslb_sites:
      ${ indent(6, yamlencode(additional_gslb_sites))}
%{ if vip_allocation_strategy == "ILB" ~}
    cloud_router: ${cloud_router}
%{ endif ~}
%{ if avi_upgrade.enabled || register_controller.enabled  ~}
    avi_upgrade:
      enabled: ${avi_upgrade.enabled}
    register_controller:
      enabled: ${register_controller.enabled}
%{ endif ~}
  tasks:
    - name: Wait for Controller to become ready
      wait_for:
        port: 443
        timeout: 600
        sleep: 5
    - name: Configure System Configurations
      avi_systemconfiguration:
        avi_credentials: "{{ avi_credentials }}"
        state: present
        email_configuration:
          smtp_type: "SMTP_LOCAL_HOST"
          from_email: admin@avicontroller.net
        global_tenant_config:
          se_in_provider_context: true
          tenant_access_to_provider_se: true
          tenant_vrf: false
%{ if dns_servers != null ~}
        dns_configuration:
          server_list: "{{ dns_servers }}"
          search_domain: "{{ dns_search_domain }}"
%{ endif ~}
        ntp_configuration:
          ntp_servers: "{{ ntp_servers }}"
        portal_configuration:
          allow_basic_authentication: false
          disable_remote_cli_shell: false
          enable_clickjacking_protection: true
          enable_http: true
          enable_https: true
          password_strength_check: true
          redirect_to_https: true
          use_uuid_from_input: false
        welcome_workflow_complete: true
        
    - name: Configure Cloud
      avi_cloud:
        avi_credentials: "{{ avi_credentials }}"
        state: present
        name: "{{ cloud_name }}"
        vtype: CLOUD_GCP
        dhcp_enabled: true
        license_type: "LIC_CORES" 
        gcp_configuration:
          region_name: "{{ region }}"
          se_project_id: "{{ se_project_id }}"
          gcs_project_id: "{{ gcs_project_id }}"
          zones: %{ for zone in zones }
            - "${zone}"
            %{ endfor }
          network_config:
            config:  "INBAND_MANAGEMENT"
            inband:
              vpc_subnet_name: "{{ vpc_subnet_name }}"
              vpc_project_id: "{{ vpc_project_id }}"
              vpc_network_name: "{{ vpc_network_name }}"
          firewall_target_tags:
            - "avi-se"
          dhcp_enabled: false
          vip_allocation_strategy:
            mode: "{{ vip_allocation_strategy }}" %{ if vip_allocation_strategy == "ILB" }
            ilb:
              cloud_router_names:
                - "{{ cloud_router }}"
            %{ endif }
%{ if se_service_account != null ~}
          gcp_service_account_email: "{{ gcp_service_account_email }}"
%{ endif ~}
      register: avi_cloud
    - name: Set Backup Passphrase
      avi_backupconfiguration:
        avi_credentials: "{{ avi_credentials }}"
        state: present
        name: Backup-Configuration
        backup_passphrase: "{{ password }}"
        upload_to_remote_host: false
%{ if se_ha_mode == "active/active" ~}
    - name: Configure SE-Group
      avi_api_session:
        avi_credentials: "{{ avi_credentials }}"
        http_method: post
        path: "serviceenginegroup"
        tenant: "admin"
        data:
          name: "Default-Group" 
          avi_credentials: "{{ avi_credentials }}"
          state: present
          cloud_ref: "{{ avi_cloud.obj.url }}"
          ha_mode: HA_MODE_SHARED_PAIR
          min_scaleout_per_vs: 2
          algo: PLACEMENT_ALGO_PACKED
          buffer_se: "0"
          max_se: "10"
          se_name_prefix: "{{ name_prefix }}"
          vcpus_per_se: "{{ se_size.cpu }}"
          memory_per_se: "{{ se_size.memory * 1024 }}"
          disk_per_se: "{{ se_size.disk }}"
          realtime_se_metrics:
            duration: "60"
            enabled: true
%{ endif ~}
%{ if se_ha_mode == "n+m" ~}
    - name: Configure SE-Group
      avi_api_session:
        avi_credentials: "{{ avi_credentials }}"
        http_method: post
        path: "serviceenginegroup"
        tenant: "admin"
        data:
          name: "Default-Group" 
          avi_credentials: "{{ avi_credentials }}"
          state: present
          cloud_ref: "{{ avi_cloud.obj.url }}"
          ha_mode: HA_MODE_SHARED
          min_scaleout_per_vs: 1
          algo: PLACEMENT_ALGO_PACKED
          buffer_se: "1"
          max_se: "10"
          se_name_prefix: "{{ name_prefix }}"
          vcpus_per_se: "{{ se_size.cpu }}"
          memory_per_se: "{{ se_size.memory * 1024 }}"
          disk_per_se: "{{ se_size.disk }}"
          realtime_se_metrics:
            duration: "60"
            enabled: true
%{ endif ~}
%{ if se_ha_mode == "active/standby" ~}
    - name: Configure SE-Group
      avi_api_session:
        avi_credentials: "{{ avi_credentials }}"
        http_method: post
        path: "serviceenginegroup"
        tenant: "admin"
        data:
          name: "Default-Group" 
          avi_credentials: "{{ avi_credentials }}"
          state: present
          cloud_ref: "{{ avi_cloud.obj.url }}"
          ha_mode: HA_MODE_LEGACY_ACTIVE_STANDBY
          min_scaleout_per_vs: 1
          buffer_se: "0"
          max_se: "2"
          se_name_prefix: "{{ name_prefix }}"
          vcpus_per_se: "{{ se_size.cpu }}"
          memory_per_se: "{{ se_size.memory * 1024 }}"
          disk_per_se: "{{ se_size.disk }}"
          realtime_se_metrics:
            duration: "60"
            enabled: true

%{ endif ~}
    - name: Configure IPAM Profile
      block:
        - name: Update IPAM Network Objects with Static Pool
          avi_network:
            avi_credentials: "{{ avi_credentials }}"
            state: present
            avi_api_update_method: patch
            avi_api_patch_op: add
            name: "network-{{ item.network }}"
            dhcp_enabled: false
            configured_subnets:
              - prefix:
                  ip_addr:
                    addr: "{{ item.network | ipaddr('network') }}"
                    type: "V4"
                  mask: "{{ item.network | ipaddr('prefix') }}"
                static_ip_ranges:
                - range:
                    begin:
                      addr: "{{ item.static_pool.0 }}"
                      type: "V4"
                    end:
                      addr: "{{ item.static_pool.1 }}"
                      type: "V4"
                  type: STATIC_IPS_FOR_VIP_AND_SE
            ip6_autocfg_enabled: false
          loop: "{{ ipam_networks }}"
          register: ipam_net
        - name: Create list with IPAM Network URLs
          set_fact: ipam_net_urls="{{ ipam_net.results | map(attribute='obj.url') | list }}"
        - name: Create list formated for Avi IPAM profile API
          set_fact:
            ipam_list: "{{ ipam_list | default([]) + [{ 'nw_ref': item  }] }}"
          loop: "{{ ipam_net_urls }}"
        - name: Create Avi IPAM Profile
          avi_ipamdnsproviderprofile:
            avi_credentials: "{{ avi_credentials }}"
            state: present
            name: Avi_IPAM
            type: IPAMDNS_TYPE_INTERNAL
            internal_profile:
              ttl: 30
              usable_networks: "{{ ipam_list }}"
            allocate_ip_in_vrf: false
          register: create_ipam
        - name: Update Cloud Configuration with IPAM profile 
          avi_api_session:
            avi_credentials: "{{ avi_credentials }}"
            http_method: patch
            path: "cloud/{{ avi_cloud.obj.uuid }}"
            data:
              add:
                ipam_provider_ref: "{{ create_ipam.obj.url }}"
      when: configure_ipam_profile == true
      tags: ipam_profile

    - name: Configure DNS Profile
      block:
        - name: Create Avi DNS Profile
          avi_ipamdnsproviderprofile:
            avi_credentials: "{{ avi_credentials }}"
            state: present
            name: Avi_DNS
            type: IPAMDNS_TYPE_INTERNAL_DNS
            internal_profile:
              dns_service_domain:
              - domain_name: "{{ dns_domain }}"
                pass_through: true
              ttl: 30
          register: create_dns
        - name: Update Cloud Configuration with DNS profile 
          avi_api_session:
            avi_credentials: "{{ avi_credentials }}"
            http_method: patch
            path: "cloud/{{ avi_cloud.obj.uuid }}"
            data:
              add:
                dns_provider_ref: "{{ create_dns.obj.url }}"
      when: configure_dns_profile == true
      tags: dns_profile

    - name: Configure GSLB SE Group and Account
      block:
        - name: Configure GSLB SE-Group
          avi_api_session:
            avi_credentials: "{{ avi_credentials }}"
            http_method: post
            path: "serviceenginegroup"
            tenant: "admin"
            data:
              name: "g-dns" 
              cloud_ref: "{{ avi_cloud.obj.url }}"
              ha_mode: HA_MODE_SHARED_PAIR
              min_scaleout_per_vs: 2
              algo: PLACEMENT_ALGO_PACKED
              buffer_se: "0"
              max_se: "4"
              max_vs_per_se: "1"
              extra_shared_config_memory: 2000
              se_name_prefix: "{{ name_prefix }}{{ gslb_site_name }}"
              vcpus_per_se: "{{ gslb_se_size.cpu }}"
              memory_per_se: "{{ gslb_se_size.memory * 1024 }}"
              disk_per_se: "{{ gslb_se_size.disk }}"
              realtime_se_metrics:
                duration: "60"
                enabled: true
          register: gslb_se_group

        - name: Create User for GSLB
          avi_user:
            avi_credentials: "{{ avi_credentials }}"
            default_tenant_ref: "/api/tenant?name=admin"
            state: present
            name: "{{ gslb_user }}"
            access:
              - all_tenants: true
                role_ref: "/api/role?name=System-Admin"
            email: "{{ user_email | default(omit) }}"
            user_profile_ref: "/api/useraccountprofile?name=No-Lockout-User-Account-Profile"
            is_superuser: false
            obj_password: "{{ password }}"
            obj_username: "{{ gslb_user }}"
      when: configure_gslb == true or create_gslb_se_group == true
      tags: gslb

    - name: Configure DNS Virtual Service
      block:
        - name: Create DNS VSVIP
          avi_api_session:
            avi_credentials: "{{ avi_credentials }}"
            http_method: post
            path: "vsvip"
            tenant: "admin"
            data:
              east_west_placement: false
              cloud_ref: "{{ avi_cloud.obj.url }}"
%{ if configure_gslb || create_gslb_se_group ~}
              se_group_ref: "{{ gslb_se_group.obj.url }}"
%{ endif ~}
              vip:
              - enabled: true
                vip_id: 0
%{ if dns_vs_settings.auto_allocate_ip == "false" ~}
                ip_address:
                  addr: "{{ dns_vs_settings.vs_ip }}"
                  type: "V4"
%{ endif ~}            
                auto_allocate_ip: "{{ dns_vs_settings.auto_allocate_ip }}"
%{ if dns_vs_settings.auto_allocate_ip ~}
                auto_allocate_floating_ip: "{{ dns_vs_settings.auto_allocate_public_ip }}"
%{ endif ~}
                avi_allocated_vip: false
                avi_allocated_fip: false
                auto_allocate_ip_type: V4_ONLY
                prefix_length: 32
                placement_networks: []
                ipam_network_subnet:
                  network_ref: "/api/network/?name=network-{{ dns_vs_settings.network }}"
                  subnet:
                    ip_addr:
                      addr: "{{ dns_vs_settings.network | ipaddr('network') }}"
                      type: V4
                    mask: "{{ dns_vs_settings.network | ipaddr('prefix') }}"
              dns_info:
              - type: DNS_RECORD_A
                algorithm: DNS_RECORD_RESPONSE_CONSISTENT_HASH
                fqdn: "dns.{{ dns_domain }}"
              name: vsvip-DNS-VS-Default-Cloud
          register: vsvip_results

        - name: Display DNS VS VIP
          ansible.builtin.debug:
            var: vsvip_results

        - name: Create DNS Virtual Service
          avi_api_session:
            avi_credentials: "{{ avi_credentials }}"
            http_method: post
            path: "virtualservice"
            tenant: "admin"
            data:
              name: DNS-VS
              enabled: true
              analytics_policy:
                full_client_logs:
                  enabled: true
                  duration: 30
                metrics_realtime_update:
                  enabled: true
                  duration: 30
              traffic_enabled: true
              application_profile_ref: /api/applicationprofile?name=System-DNS
              network_profile_ref: /api/networkprofile?name=System-UDP-Per-Pkt
              analytics_profile_ref: /api/analyticsprofile?name=System-Analytics-Profile
              %{ if configure_gslb || create_gslb_se_group }
              se_group_ref: "{{ gslb_se_group.obj.url }}"
              %{ endif}
              cloud_ref: "{{ avi_cloud.obj.url }}"
              services:
              - port: 53
                port_range_end: 53
              - port: 53
                port_range_end: 53
                override_network_profile_ref: /api/networkprofile/?name=System-TCP-Proxy
              vsvip_ref: "{{ vsvip_results.obj.url }}"
          register: dns_vs

        - name: Add DNS-VS to System Configuration
          avi_systemconfiguration:
            avi_credentials: "{{ avi_credentials }}"
            avi_api_update_method: patch
            avi_api_patch_op: add
            tenant: admin
            dns_virtualservice_refs: "{{ dns_vs.obj.url }}"
      when: configure_dns_vs == true
      tags: configure_dns_vs

    - name: Configure GSLB
      block:
        - name: GSLB Config | Verify Cluster UUID
          avi_api_session:
            avi_credentials: "{{ avi_credentials }}"
            http_method: get
            path: cluster
          register: cluster

        - name: Create GSLB Config
          avi_gslb:
            avi_credentials: "{{ avi_credentials }}"
            name: "GSLB"
            sites:
              - name: "{{ gslb_site_name }}"
                username: "{{ gslb_user }}"
                password: "{{ password }}"
                ip_addresses:
                  - type: "V4"
                    addr: "{{ controller_ip[0] }}"
%{ if controller_ha ~}
                  - type: "V4"
                    addr: "{{ controller_ip[1] }}"
                  - type: "V4"
                    addr: "{{ controller_ip[2] }}"
%{ endif ~}
                enabled: True
                member_type: "GSLB_ACTIVE_MEMBER"
                port: 443
                dns_vses:
                  - dns_vs_uuid: "{{ dns_vs.obj.uuid }}"
                cluster_uuid: "{{ cluster.obj.uuid }}"
            dns_configs:
%{ for domain in gslb_domains ~}
              - domain_name: "${domain}"
%{ endfor ~}
            leader_cluster_uuid: "{{ cluster.obj.uuid }}"
          until: gslb_results is not failed
          retries: 30
          delay: 5
          register: gslb_results
      when: configure_gslb == true
      tags: configure_gslb

    - name: Configure Additional GSLB Sites
      block:
%{ for site in additional_gslb_sites ~}
        - name: GSLB Config | Verify Remote Site is Ready
          avi_api_session:
            controller: "${site.ip_address_list[0]}"
            username: "{{ gslb_user }}"
            password: "{{ password }}"
            api_version: "{{ api_version }}"
            http_method: get
            path: virtualservice?name=DNS-VS
          until: remote_site_check is not failed
          retries: 30
          delay: 10
          register: remote_site_check

        - name: GSLB Config | Verify DNS configuration
          avi_api_session:
            controller: "${site.ip_address_list[0]}"
            username: "{{ gslb_user }}"
            password: "{{ password }}"
            api_version: "{{ api_version }}"
            http_method: get
            path: virtualservice?name=DNS-VS
          until: dns_vs_verify is not failed
          failed_when: dns_vs_verify.obj.count != 1
          retries: 30
          delay: 10
          register: dns_vs_verify

        - name: Display DNS VS Verify
          ansible.builtin.debug:
            var: dns_vs_verify

        - name: GSLB Config | Verify GSLB site configuration
          avi_api_session:
            avi_credentials: "{{ avi_credentials }}"
            http_method: post
            path: gslbsiteops/verify
            data:
              name: name
              username: "{{ gslb_user }}"
              password: "{{ password }}"
              port: 443
              ip_addresses:
                - type: "V4"
                  addr: "${site.ip_address_list[0]}"
          register: gslb_verify
      
        - name: Display GSLB Siteops Verify
          ansible.builtin.debug:
            var: gslb_verify

        - name: Add GSLB Sites
          avi_api_session:
            avi_credentials: "{{ avi_credentials }}"
            http_method: patch
            path: "gslb/{{ gslb_results.obj.uuid }}"
            tenant: "admin"
            data:
              add:
                sites:
                  - name: "${site.name}"
                    member_type: "GSLB_ACTIVE_MEMBER"
                    username: "{{ gslb_user }}"
                    password: "{{ password }}"
                    cluster_uuid: "{{ gslb_verify.obj.rx_uuid }}"
                    ip_addresses:
%{ for address in site.ip_address_list ~}
                      - type: "V4"
                        addr: "${address}"
%{ endfor ~}
                    dns_vses:
                      - dns_vs_uuid: "{{ dns_vs_verify.obj.results.0.uuid }}"
%{ endfor ~}
      when: configure_gslb_additional_sites == true
      tags: configure_gslb_additional_sites

    - name: Controller Cluster Configuration
      avi_cluster:
        avi_credentials: "{{ avi_credentials }}"
        state: present
        #virtual_ip:
        #  type: V4
        #  addr: "{{ controller_cluster_vip }}"
        nodes:
            - name:  "{{ controller_names[0] }}" 
              password: "{{ password }}"
              ip:
                type: V4
                addr: "{{ controller_ip[0] }}"
            - name:  "{{ controller_names[1] }}" 
              password: "{{ password }}"
              ip:
                type: V4
                addr: "{{ controller_ip[1] }}"
            - name:  "{{ controller_names[2] }}" 
              password: "{{ password }}"
              ip:
                type: V4
                addr: "{{ controller_ip[2] }}"
%{ if configure_gslb || create_gslb_se_group ~}
        name: "{{ name_prefix }}-{{ gslb_site_name }}-cluster"
%{ else ~}
        name: "{{ name_prefix }}-cluster"
%{ endif ~}
        tenant_uuid: "admin"
      until: cluster_config is not failed
      retries: 10
      delay: 5
      register: cluster_config
      when: controller_ha == true
      tags: controller_ha

    - name: Add Prerequisites for avi-cloud-services-registration.yml Play
      block:
        - name: Install Avi Collection
          shell: ansible-galaxy collection install vmware.alb -p /home/admin/.ansible/collections

        - name: Copy Ansible module file
          ansible.builtin.copy:
            src: /home/admin/avi_pulse_registration.py
            dest: /home/admin/.ansible/collections/ansible_collections/vmware/alb/plugins/modules/avi_pulse_registration.py
        
        - name: Remove unused module file
          ansible.builtin.file:
            path: /home/admin/avi_pulse_registration.py
            state: absent
%{ if split(".", avi_version)[0] == "21" && split(".", avi_version)[2] == "4"  ~}

        - name: Patch file
          shell: patch --directory /opt/avi/python/bin/portal/api/ < /home/admin/views_albservices.patch

        - name: Restart Avi Portal
          ansible.builtin.systemd:
            state: restarted
            name: aviportal
%{ endif ~}
      tags: register_controller

    - name: Remove patch file
      ansible.builtin.file:
        path: /home/admin/views_albservices.patch
        state: absent

%{ if avi_upgrade.enabled || register_controller.enabled  ~}

    - name: Verify Cluster State if avi_upgrade or register_controller plays will be ran
      block:
        - name: Pause for 8 minutes for Cluster to form
          ansible.builtin.pause:
            minutes: 8
    
        - name: Wait for Avi Cluster to be ready
          avi_api_session:
            avi_credentials: "{{ avi_credentials }}"
            http_method: get
            path: "cluster/runtime"
          until: cluster_check is not failed
          retries: 60
          delay: 10
          register: cluster_check

        - name: Wait for Avi Cluster to be ready
          avi_api_session:
            avi_credentials: "{{ avi_credentials }}"
            http_method: get
            path: "cluster/runtime"
          until: cluster_runtime.obj.cluster_state.state == "CLUSTER_UP_HA_ACTIVE"
          retries: 60
          delay: 10
          register: cluster_runtime
      when: (controller_ha == true and avi_upgrade.enabled == true) or
            (controller_ha == true and register_controller.enabled == true)
      tags: verify_cluster
%{ endif ~}