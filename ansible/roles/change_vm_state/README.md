Changing EC2 VM state
=========

Role for changing EC2 VM state

Requirements
------------

Uses https://docs.ansible.com/ansible/latest/modules/ec2_module.html

 - python >= 2.6
 - boto

Role Variables
--------------

    # Required vm state, allowed: [absent, running, restarted, stopped]
    vm_state: 
    # List of instance ids or one id
    instance_ids: 

Dependencies
------------

None

Example Playbook
----------------

Including an example of how to use your role (for instance, with variables passed in as parameters) is always nice for users too:

    - name: Start VM
      hosts: localhost
      connection: local
      gather_facts: False
      vars:
        vm_state: running
        instance_ids: 
          - id1
          - id2
      roles:
        - change_vm_state

License
-------

Apache