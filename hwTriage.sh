#! /usr/bin/env python3
# Copyright 2023 Hewlett Packard Enterprise Development LP

import os
import sys
import subprocess
import argparse
import re
import datetime
import getpass
import json

cwd=os.path.abspath(os.path.join(os.path.dirname(__file__)))
sys.path.insert(1, cwd+"/custom_scripts")
sys.path.insert(2, cwd+"/utils")
LIB_PATH=cwd+"/lib/python"
sys.path.insert(1, LIB_PATH)
import yaml
import logger
import loader
from json_reader import json_reader
from custom_script_runner import custom_script_runner
from check_hardware import check_hardware
from functions import *
from node_power_status import get_xname
global data
global json_dict
global nc
global hardware
global bios
global node
global run_all_stages
global username
global password
global hardware_file
global log_path
global log_flag
global default_log_dir
default_log_dir = '/var/log/hardware-triage-tool'

def functions_to_exec(func_list,start_func):
    try:
        start_index=func_list.index(start_func)
        #for index in range(start_index,len(func_list)):
        #    print(func_list[index])
    except ValueError:
        print(f"Error: {start_func} is not in the function list.")
        return []
    return func_list[start_index:]


def yes_no_condition_exec(func_list,start_func,condition,json_dict):
    try:
        if("action" in data[start_func][condition]):
            if '$logpath' in data[start_func][condition]["action"]:
                data[start_func][condition]["action"] = data[start_func][condition]["action"].replace('$logpath',log_path)
            if run_all_stages:
                print("Recommended  action : ",data[start_func][condition]["action"])
                logger.add_global_key(analysis_file,"Recommended  action",data[start_func][condition]["action"])
            else:
                print("Exiting as running stage ", start_func," Completed!")
                print("Recommended  action : ",data[start_func][condition]["action"])
                logger.add_global_key(analysis_file,"Recommended  action",data[start_func][condition]["action"])
                sys.exit(0)
        if("run_func" in data[start_func][condition]):
            if run_all_stages:
                script_name=data[start_func][condition]["run_func"]
                if node is None or username is None or password is None:
                    os.system("python3 "+cwd+"/custom_scripts/"+ script_name+" "+log_path+" "+hardware)
                else:
                    os.system("python3 "+cwd+"/custom_scripts/"+ script_name+" "+log_path+" "+hardware+" "+nc+" "+username+" "+password)
            else:
                script_name=data[start_func][condition]["run_func"]
                if node is None or username is None or password is None:
                    os.system("python3 "+cwd+"/custom_scripts/"+ script_name+" "+log_path+" "+hardware)
                else:
                    os.system("python3 "+cwd+"/custom_scripts/"+ script_name+" "+log_path+" "+hardware+" "+nc+" "+username+" "+password)
                print("Exiting as running stage ", start_func," Completed!")
                sys.exit(0)
        if("go_to" in data[start_func][condition]):
            if run_all_stages:
                process_final_func(func_list,data[start_func][condition]["go_to"],json_dict)
            else:
                print("Exiting as running stage ", start_func," Completed!")
                sys.exit(0)
        if(data[start_func][condition] == "None"):
            print("Triage Completed!")
            sys.exit(0)
    except KeyError:
        print(f"Error: '{condition}' does not specify a 'run_func' for '{start_func}'.")

def func_to_return_parsed(parser,result,start_func):
    json_input = result
    parser = eval(f"[{parser}]")
    for key_set in parser:
        key_count = 0
        result=json_input
        for primary_key in key_set:
            components = {}
            if type(primary_key) is list:
                for i in primary_key:
                    if result[i] not in components:
                        components[result[i]] = [i]
                    else:
                        components[result[i]].append(i)
                return components
            else:
                try:
                    result = result[primary_key]
                    key_count+=1
                    if key_count==len(key_set):
                        return result
                except:
                    logger.add_logs_to_triage_key(analysis_file,start_func,primary_key,f"key not found in key_set {key_set} of input json file")
                    break
    print("Provided keys not found. Details available in the analysis file, Exiting!")
    exit(1)

def func_to_collect_value(start_func,key,json_data):
    #print(start_func,key,json_data)
    result=json_data
    value_dict={}
    for final_key in data[start_func][key].keys():
        if "input" in final_key:
            parser=data[start_func][key][final_key]
            x=func_to_return_parsed(parser,result,start_func)
            value_dict[final_key]= x
    if(len(value_dict)==1):
        return next(iter(value_dict.values()))
    else:
        return value_dict


def value_processor(func_list,start_func,key,output):
    if(key=="custom_script"):
        output=str(output)
        custom_keys=data[start_func].keys()
        if("custom_script_value_yes" in custom_keys):
            if(output==data[start_func]["custom_script_value_yes"]):
                return 1
            else:
                return 0
        else:
            if("custom_script_value_no" in custom_keys):
                if(output==data[start_func]["custom_script_value_no"]):
                    return 0
                else:
                    return 1

    if(key=="exec_statement"):
        exec_keys=data[start_func].keys()
        if("exec_statement_value_yes" in exec_keys):
            if(output==data[start_func]["exec_statement_value_yes"]):
                return 1
            else:
                return 0
        else:
            if("exec_statement_value_no" in exec_keys):
                if(output==data[start_func]["exec_statement_value_no"]):
                    return 0
                else:
                    return 1

    if("key" in key):
        value_collected=func_to_collect_value(start_func,key,output)
        if("value" in data[start_func][key].keys()):
            value_keys=data[start_func][key]["value"].keys()
            if("value_reassign" in value_keys):
                if("perform_action_&" in data[start_func][key]["value"]["value_reassign"]):
                    value_collected=perform_and_operation(value_collected)
                if("compare_inputs" in data[start_func][key]["value"]["value_reassign"]):
                    value_collected=compare_inputs_sts_msk(value_collected)
            if("value_yes" in value_keys):
                if type(value_collected) is dict:
                    if data[start_func][key]["value"]["value_yes"] in value_collected:
                        p = ','.join(value_collected[data[start_func][key]["value"]["value_yes"]])
                        print("\033[1;31;40m" + p + "\033[0m"+" has met the condition for "+ start_func)
                        return 1
                    else:
                        return 0
                elif(value_collected==data[start_func][key]["value"]["value_yes"]):
                    return 1
                else:
                    return 0
            if("value_no" in value_keys):
                if type(value_collected) is dict:
                    if data[start_func][key]["value"]["value_no"] in value_collected:
                        p = ','.join(value_collected[data[start_func][key]["value"]["value_no"]])
                        print("\033[1;31;40m"  + str(p) + "\033[0m"+ " has met the condition for "+ start_func)
                        return 0
                    else:
                        return 1
                if(value_collected==data[start_func][key]["value"]["value_no"]):
                    return 0
                else:
                    return 1

def process_final_func(func_list,start_func,json_dict):
    global log_flag
    global nc
    global node
    function_final_bool=1
    logger.add_key_to_triage_json(analysis_file,start_func)
    keys=data[start_func].keys()
    if(verbosity):
            print("Starting stage", start_func, "Check")
    if("input_json" in keys):
        if '$n' in data[start_func]["input_json"]:
            node_id=(node).split("n")[1]
            if log_flag:
                node_id=get_node_num(log_path)
            data[start_func]["input_json"] = data[start_func]["input_json"].replace('$n', node_id)


        json_data,json_dict=json_reader(log_path+"/"+data[start_func]["input_json"],json_dict)
        logger.add_logs_to_triage_key(analysis_file,start_func,"Input json file ",data[start_func]["input_json"])
        if(verbosity):
            print("Input json file : "+data[start_func]["input_json"])
    if("exec_statement" in keys):
        if "$logpath" in data[start_func]["exec_statement"]:
            data[start_func]["exec_statement"] = data[start_func]["exec_statement"].replace("$logpath",log_path)
            command=(data[start_func]["exec_statement"]).strip().split(" ")
            output = subprocess.check_output(command)
            output = output.decode()
            output = output.strip()
            function_final_bool=value_processor(func_list,start_func,"exec_statement",output.strip())

        else:
            if log_flag:
                print("Stage", start_func, "Not Supported, not able to access NC")
                function_final_bool = 0 if data[start_func]["exec_statement_value_yes"] == "1" else 1
            else:
                oldpdshkey=os.environ.get('PDSH_SSH_ARGS_APPEND')
                os.environ.pop('PDSH_SSH_ARGS_APPEND', None)
                command=('pdsh -w ' + nc +" "+ data[start_func]["exec_statement"]).split(" ")
                output = subprocess.check_output(command)
                output = output.decode()
                os.environ['PDSH_SSH_ARGS_APPEND']=oldpdshkey
                listOfWords = output.split(":", 1)
                if len(listOfWords) > 0:
                   output = listOfWords[1]
                function_final_bool=value_processor(func_list,start_func,"exec_statement",output.strip())


    if("custom_script" in keys):
        try:
            if "custom_script_args" in data[start_func]:
                if data[start_func]["custom_script_args"] == 'nc':
                    if log_flag:
                        print("Stage", start_func, "Not Supported, not able to access NC")
                        return_code = 0 if data[start_func]["custom_script_value_yes"] == "1" else 1
                    else:
                        node_id=(node).split("n")[1]
                        return_code= custom_script_runner(data[start_func]["custom_script"],nc+" "+username+" "+password+" "+hardware_file+" " +hardware+" "+node_id+ " "+log_path)
                elif data[start_func]["custom_script_args"] == 'log_path':
                    return_code= custom_script_runner(data[start_func]["custom_script"],log_path+" "+hardware_file+" "+hardware)
                elif data[start_func]["custom_script_args"] == 'node':
                    if log_flag:
                        print("Stage", start_func, "Not Supported, not able to access node")
                        return_code = 0 if data[start_func]["custom_script_value_yes"] == "1" else 1
                    else:
                        return_code= custom_script_runner(data[start_func]["custom_script"],node+" "+log_path+" "+hardware_file+" "+hardware)
                else:
                    return_code= custom_script_runner(data[start_func]["custom_script"],data[start_func]["custom_script_args"])
            else:
                return_code= custom_script_runner(data[start_func]["custom_script"])
        except Exception as e:
            print("Failed to execute custom script: ",data[start_func]["custom_script"],"\nError:",e)
            return_code = "0" if data[start_func]["custom_script_value_yes"] == "1" else "1"

        function_final_bool=value_processor(func_list,start_func,"custom_script",return_code)
    for key in data[start_func]:
        if 'key' in key:
            if '$n' in data[start_func][key]["input"]:
                node_id=(node).split("n")[1]
                if log_flag:
                    node_id=get_node_num(log_path)
                node_id=str(int(node_id) % 2)
                data[start_func][key]["input"] = data[start_func][key]["input"].replace('$n', node_id)
            function_final_bool=value_processor(func_list,start_func,key,json_data)

    if("yes_condition" in keys and function_final_bool==1):
        stage_output=start_func+" Detected!"
        logger.add_logs_to_triage_key(analysis_file,start_func,"Stage analysis", stage_output)
        print("Stage analysis :",start_func, "Detected!")
        yes_no_condition_exec(func_list,start_func,"yes_condition",json_dict)
    if("no_condition" in keys and function_final_bool==0):
        stage_output="NO "+start_func+" Detected!"
        logger.add_logs_to_triage_key(analysis_file,start_func,"Stage analysis", stage_output)
        if(verbosity):
            print("Stage analysis :No ",start_func , "Detected!")
        yes_no_condition_exec(func_list,start_func,"no_condition",json_dict)


def validate_hardware(hardware_param,hardware_file):
    global hardware
    config_data = read_yaml(hardware_file)
    for item in config_data['hardware_family']:
        if hardware_param:
            if  hardware_param.lower() == item['name'].lower():
                hardware = item['name'].lower()
                return 1
    return 0

def workflow_on(hardware, hardware_file):
    config_data = read_yaml(hardware_file)
    for item in config_data['hardware_family']:
        if hardware == item['name']:
            return item['attributes']['hardware']['workflow_on']

def workflow_off(hardware, hardware_file):
    config_data = read_yaml(hardware_file)
    for item in config_data['hardware_family']:
        if hardware == item['name']:
            return item['attributes']['hardware']['workflow_off']

def node_state_check(nodename,username,password):
    node_state = "" ; begin_stage = ""
    global boot_var
    command=['python3',cwd+'/utils/node_power_status.py','--node', nodename, '--username',username, '--password',password ]
    result = subprocess.run(command,stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    output = result.stdout.decode()

    if "Invalid Credentials" in output or "not present" in output :
        print(output)
        return node_state,begin_stage

    if result.returncode == 1:
        print("Unable to check Node status:",nodename)
        return node_state,begin_stage

    #output = "Off"
    if "Off" in output:
        node_state = "Off"
        return node_state,begin_stage
    elif "On" in output:
        node_state = "On"

        command=('pdsh -w ' + nodename +" "+ "uptime").split(" ")
        output = subprocess.run(command,stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        output = output.stdout.decode()
        if "up" in output:
            boot_var = "Node is booted"
            begin_stage = "CheckNodeHealth_Failure"
            return node_state, begin_stage
        else:
            boot_var = "Node is not booted"
            begin_stage = "Dracut_shell"
            return node_state,begin_stage

def pre_run_setup(args_yaml=None):
    global data ; global analysis_file; global log_path; global serial_number_file; global boot_var; global log_flag
    file_name=""
    print("Node is in " + node_state + " state")
    if node_state == 'On' and log_flag == 0:
        print(boot_var)
    analysis_file=log_path+"/triage_output.json"
    if log_flag:
        if os.path.exists((log_path)+"/serial_numbers.txt"):
            serial_number_file = log_path + "/serial_numbers.txt"
        else:
            serial_number_file=""
    else:
        serial_number_file = log_path + "/serial_numbers.txt"
    logger.create_json_backup(node_state,analysis_file)
    if args_yaml:
        file_name = args_yaml
    else:
        workflow_on_yml = workflow_on(hardware, hardware_file)
        workflow_off_yml = workflow_off(hardware, hardware_file)
        if "Off" in node_state:
            file_name = cwd+"/"+workflow_off_yml
        else:
            file_name = cwd+"/"+workflow_on_yml
    data = read_yaml(file_name)
    json_dict={}
    functions_in_yaml=list(data.keys())
    input_func=functions_in_yaml[0]
    print("Analysis file : ",analysis_file)
    if serial_number_file:
        print("Serial Numbers information : ", serial_number_file)
    else:
        print("Serial Numbers information : Serial number file doesn't exist in the provided log path")
    final_func_list=functions_to_exec(functions_in_yaml,input_func)
    return final_func_list

def run_flow_process_func(final_func_list, node_state, begin_stage):
    try:
        if begin_stage:
            json_dict={}
            process_final_func(final_func_list,begin_stage,json_dict)
        else:
            json_dict={}
            process_final_func(final_func_list,final_func_list[0],json_dict)
    except KeyError:
        print(begin_stage + " not supported when the node is "+node_state)
        logger.add_logs_to_triage_key(analysis_file,begin_stage,"Incorrect key ", begin_stage+ " is not supported when the node is "+node_state)
    return 0

def get_functions_in_yaml(args_yaml=None):
    if args_yaml:
        file_name = args_yaml
    else:
        workflow_on_yml = workflow_on(hardware, hardware_file)
        workflow_off_yml = workflow_off(hardware, hardware_file)
        if "Off" in node_state:
            file_name = cwd+"/"+workflow_off_yml
        else:
            file_name = cwd+"/"+workflow_on_yml
    data = read_yaml(file_name)
    functions_in_yaml=list(data.keys())
    return functions_in_yaml

def generateParser():
    parser = argparse.ArgumentParser(description="This is a triaging tool which checks the nodes for various issues and produces the same on the console. It accepts nodename as the required argument and multiple optional arguments which can be passed as needed. The description of the arguments are displayed below.")

    group = parser.add_mutually_exclusive_group(required=True)

    group.add_argument("-r", "--revision", action='store_true', help="Show the revision and exit.")

    group.add_argument("-n", "--node-name", help="Enter the node name to perform the checks")
    parser.add_argument("-u", "--username", required=False, help="Username to access node controller and the redfish calls")
    parser.add_argument("-p", "--password", required=False, help="Password to access node controller and redfish calls")

    group.add_argument("-l", "--logpath", help="Provide the full log path to perform the checks")
    parser.add_argument("-ns", "--node-state", required=False, help="Provide the node power state", choices=['On', 'Off'])
    parser.add_argument("-hw", "--hardware", required=False, help="Provide the node hardware type", choices=["ex235a","ex255a","ex254n","ex4252","ex425","ex235n"])

    parser.add_argument("-ls", "--list-stages", required=False, action='store_true', help="To list stages in a yaml file")
    parser.add_argument("-bs", "--begin-stage", required=False, help="Enter the stage name from where the check will start")
    parser.add_argument("-rs", "--run-stage", required=False, help="To run only one stage from yaml file")
    parser.add_argument("-f", "--input-yaml", required=False, help="To pass an input config yml file as input")
    parser.add_argument("-hy", "--hardware-yaml", required=False, help="To pass a hardware config yml file as input")
    parser.add_argument("-sn", "--show-serial-number", required=False, action='store_true', help="To display the serial number info with the triage result")
    parser.add_argument("-sno","--serial-number-only", required=False, action='store_true',help="Collect the serial numbers into a file without triaging")
    parser.add_argument("-k", "--ssh-key", required=False, help="Ssh key to enable passwordless ssh")
    parser.add_argument("-t", "--timeout", required=False, help="Timeout duration for collecting logs in seconds, default=120")
    parser.add_argument("-v", "--verbose", required=False, action='store_true', help="To have a verbose output")
    parser.add_argument("-cpath", "--custom-log-path", required=False, help="Provide the custom log path to store the triage logs in the case to override the default log path")

    return parser

def get_node_state(args):
    node_state = "" ; begin_stage = ""; global log_path; global log_flag
    # if log_path provided
    if args.logpath:
        if args.username or args.password or args.custom_log_path:
            parser.error("If --logpath is selected, do not use --username , --password and --custom_log_path.")
            sys.exit(1)
        if not args.node_state or not args.hardware:
            parser.error("If --logpath is selected, --node_state and -hw are required.")
            sys.exit(1)
        if args.node_state == 'On':
            begin_stage = "Dracut_shell"
        log_path = args.logpath
        log_flag = 1
        node_state = args.node_state
        return node_state, begin_stage,"node",""

    #if node_name provided
    if args.node_name:
        if args.logpath or args.node_state or args.hardware:
            parser.error("If --node_name is selected, do not use --logpath, -ns, or -hw.")
            sys.exit(1)
        if not args.username:
            parser.error("--username is required when --node_name is selected.")
            sys.exit(1)
        if args.password:
            password = args.password
        else:
            try:
                password = getpass.getpass(prompt='Enter the password to access redfish calls :')
            except Exception as error:
                print('ERROR', error)
                sys.exit(1)
        if args.custom_log_path:
            log_path = args.custom_log_path
    log_flag = 0
    node = get_xname(args.node_name)

    #check if node state is on or off and validate hardware
    if args.ssh_key:
        os.environ['PDSH_SSH_ARGS_APPEND'] = '-o StrictHostKeyChecking=no -o ConnectTimeout=60 -o BatchMode=yes -i '+args.ssh_key
    else:
        os.environ['PDSH_SSH_ARGS_APPEND'] = '-o StrictHostKeyChecking=no -o ConnectTimeout=60 -o BatchMode=yes'

    username = args.username;
    node_state, begin_stage = node_state_check(node,username,password)

    return node_state, begin_stage, node, password


def copy_logs(node,hardware,serial_num_flag,serial_num_only_flag,timeout_sec,custom_log_path=None):
    try:
        global log_path
        global nc
        current_time = datetime.datetime.now()
        formatted_time = current_time.strftime('%Y%m%d_%H%M')
        nc = (node).split("n")[0]
        if custom_log_path:
            log_path = custom_log_path+"/"+node+"_"+formatted_time+"/"+nc
        else:
            log_path = default_log_dir+"/"+node+"_"+formatted_time+"/"+nc
        node_id = (node).split("n")[1]
        bash_script_path = cwd+"/utils/collect_logs.sh"
        serial_num_script_path = cwd+"/utils/collect_serial_numbers.py"
        generate_json_script = cwd+"/utils/nfpga_print_regs"
        if serial_num_only_flag:
            result=subprocess.run(['python3', serial_num_script_path, log_path, username, password,  nc, node_id, hardware], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if result.stderr:
                print(result.stderr.decode())
                print("Unable to collect Serial Numbers")
                sys.exit(1)
            else:
                print("Serial Number file information: " + log_path + "/serial_numbers.txt\n")
                if serial_num_flag:
                    print(result.stdout.decode())
                sys.exit(0)
        copying_logs_loader = loader.Loader(desc="Copying logs from Node controller :"+nc+"   ",end="Log collection completed", timeout=0.05).start()
        result1=subprocess.run(['bash', bash_script_path, nc, node_id, log_path,  generate_json_script, hardware], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout_sec)
        result2=subprocess.run(['python3', serial_num_script_path, log_path, username, password,  nc, node_id, hardware], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if("No such file or directory" in result1.stderr.decode('utf-8')):
            print("\nError:\n")
            print("\n".join(line for line in result1.stderr.decode().splitlines() if "Broken pipe" not in line and "key" not in line))
            print("generating the files...")
            # exit(1)
        if("Permission denied" in result1.stderr.decode('utf-8') or "Connection refused" in result1.stderr.decode('utf-8')):
            print("\nError:\n")
            print("Unable to collect logs from NC, Please verify whether passwordless SSH is enabled or if the controller is accessible.")
            print(result1.stdout.decode())
            sys.exit(1)
        if serial_num_flag:
            if result2.stderr:
                print(result2.stderr.decode())
                print("Unable to collect Serial Numbers")
            else:
                print(result2.stdout.decode())
        copying_logs_loader.stop()
        print("\n")
    except subprocess.TimeoutExpired:
        print("Unable to copy logs Timeout Error Occured")
        sys.exit(1)
    except Exception as e:
        print("Unable to copy logs")
        sys.exit(1)

if __name__ == "__main__":
    global analysis_file; global verbosity
    run_all_stages=True; serial_num_flag = False; serial_num_only_flag = False

    parser = generateParser()
    args = parser.parse_args()

    if args.revision:
        with open(cwd+"/.rpm_version", "r", errors='ignore') as file:
            contents = file.read()
        print("hardware triage tool revision:",contents)
        sys.exit(1)

    verbosity=False
    if args.verbose:
        verbosity=True

    if args.show_serial_number:
        serial_num_flag = True

    if args.serial_number_only:
        serial_num_only_flag = True

    node_state, begin_stage, node, password = get_node_state(args)
    username = args.username

    if log_flag:
        if serial_num_flag:
            if os.path.exists((args.logpath)+"/serial_numbers.txt"):
                with open((args.logpath)+"/serial_numbers.txt", errors='ignore') as f:
                    print(f.read())

    if node_state:
        if args.node_name:
            hardware,bios = check_hardware(node,username,password)
            if hardware == None:
                hardware = bios
        else:
            hardware = args.hardware
            bios = ""
    else:
        sys.exit(1)

    if args.hardware_yaml:
        if(os.path.exists(args.hardware_yaml)):
            pass
        else:
            print("Hardware config file does not exist, exiting!")
            sys.exit(1)
        hardware_file=args.hardware_yaml
    else:
        hardware_file=cwd+"/hardware.yml"
    validated = validate_hardware(hardware,hardware_file)

    if args.list_stages:
        functions_in_yaml=get_functions_in_yaml(args.input_yaml)
        print("List of functions present in the yaml file are: \n",functions_in_yaml,"\n\n")
        sys.exit(0)

    if args.node_name:
        try:
            timeout = int(args.timeout) if args.timeout and int(args.timeout) >= 120 else 120
        except (ValueError, TypeError):
            timeout = 120
        copy_logs(node,hardware,serial_num_flag,serial_num_only_flag,timeout,args.custom_log_path)
    print("logging path : ",log_path)


    if validated:
        print(hardware+" Hardware is supported!")
        #collect logs from node controller

        triage_loader = loader.Loader(desc="Triaging :"+node+"   ",end="Triage completed!", timeout=0.05).start()
        print("\n")
        if args.run_stage:
            run_all_stages=False
            final_func_list=pre_run_setup(args.input_yaml)
            json_dict={}
            if(args.run_stage in final_func_list):
                process_final_func(args.run_stage,args.run_stage,json_dict)
            else:
                print(args.run_stage," Is not a valid stage in yaml file, Exiting!")
                sys.exit(0)
        if args.begin_stage:
            final_func_list=pre_run_setup(args.input_yaml)
            run_flow_process_func(final_func_list,node_state,args.begin_stage)
        else:
            final_func_list=pre_run_setup(args.input_yaml)
            if args.input_yaml:
                run_flow_process_func(final_func_list,node_state,final_func_list[0])
            else:
                run_flow_process_func(final_func_list,node_state,begin_stage)
        triage_loader.stop()
    else:
        print(hardware+ " Hardware not supported in hardware config file, ",hardware_file, "exiting...")

