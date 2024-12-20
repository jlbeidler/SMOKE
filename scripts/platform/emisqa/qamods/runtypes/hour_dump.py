from __future__ import print_function
from qamods.data_file import DataFile
import numpy as np
from qamods.species_array import SpeciesArray

def get_dict(species_list, file_name, all_hours = False, grid = '', grid_desc = '', ignore_spec = False, inln = False, interpolate = False, layer = '', region = '', 
	stacks = False, ptsr = False, informat = 'NCF', verbosity = False, zip_dict = {}):
	'''
	Dumps every grid cell for every hour for each species.
	'''
	if not file_name: 
		raise ValueError('You must specify an input filename using the -f argument.')
#	if region: 
#     	    raise ValueError('This run type does not support grid to fips conversion.  Please remove -e argument from command line.')

	file1 = DataFile(file_name, verbosity, informat, ptsr, zip_dict)

	print('Writing Domain...')
	outDict = dict()

	for species_name in species_list:
		if verbosity: 
			print('Creating domain total for species: %s' %species_name)

		if species_name not in file1.species_list and ignore_spec:
			print('WARNING: The species %s does not exist in the file %s.  Skipping.' %(species_name, file1))
			continue	

		DV = SpeciesArray(file1.dump_val(species_name, all_hours, grid, grid_desc, ignore_spec, inln, layer, stacks), species_name)
		outDict[species_name] = DV

	return outDict

