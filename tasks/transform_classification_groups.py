#!/usr/bin/env python
"""This module takes two classification outputs from source and targer puppet infrastructure and
takes the user defintions from the source and adds them to the infrastructure defintions of the
target. Allowing the ability to restore a backup of user node definitions"""

import json
import sys
params = json.load(sys.stdin)
source_classification_file      = params['source_directory']+"/classification_backup.json"
target_classification_file      = params['working_directory']+"/classification_backup.json"
transformed_classification_file = params['working_directory']+"/transformed_classification.json"

def removesubgroups(data_rsg,id_rsg):
    """
    This definition allows us to traverse recursively down the json groups finding all children of
    the pe infrastructure and to remove them.

    Inputs are the resource group and parent ID of the resource groups

    Returns
    -------
    data_rsg : list
       The resource groups which did not have the parent ID
    """
    groups = list(filter(lambda x:x ["parent"]==id_rsg,data_rsg))
    for group in groups:
        subid = group["id"]
        data_rsg = list(filter(lambda x:x ["id"]!=subid,data_rsg)) # pylint: disable=cell-var-from-loop
        data_rsg = removesubgroups(data_rsg,subid)
    return data_rsg

# This defintion allows us to traverse down the pe inf tree and find all groups
def addsubgroups(data_asg,id_asg,peinf_asg):
    """
    This definition allows us to traverse recursively down the json groups finding all groups in
    the pe infrastructure tree and adding them to a list recursively and then returning the list.

    Inputs are the list of all resource groups, infrastructure resource groups found so far and
    parent ID of infrastructure groups

    Returns
    -------
    data_asg : list
       The list of resource groups of pe infrastructure groups at source
    """
    groups = list(filter(lambda x:x ["parent"]==id_asg,data_asg))
    peinf_asg = peinf_asg + groups
    for group in groups:
        subid = group["id"]
        peinf_asg = addsubgroups(data_asg,subid,peinf_asg)
    return peinf_asg

# open the backup classification
with open(source_classification_file) as data_file:
    data = json.load(data_file)
# open the DR server classification
with open(target_classification_file) as data_fileDR:
    data_DR = json.load(data_fileDR)


# find the infrastructure group and its ID
peinf = list(filter(lambda x:x ["name"]=="PE Infrastructure",data))
group_id = peinf[0]["id"]
# remove this group from the list and recursively remove all sub groups
data = list(filter(lambda x:x ["id"]!=group_id,data))
data = removesubgroups(data,group_id)

# find the dr infrastructure group and its ID
peinf_DR = list(filter(lambda x:x ["name"]=="PE Infrastructure",data_DR))
id_DR = peinf_DR[0]["id"]
# Recursively go through inf groups to get the full tree
peinf_DR = addsubgroups(data_DR,id_DR,peinf_DR)

# Add the contents of the backup classification without pe inf to the DR pe inf groups
# and write to a file
peinf_transformed_groups = data + peinf_DR
with open(transformed_classification_file, 'w') as fp:
    json.dump(peinf_transformed_groups, fp)
    