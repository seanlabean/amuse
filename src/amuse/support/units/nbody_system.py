"""
"""
from amuse.support.units import units
from amuse.support.units import core

import numpy

class nbody_unit(core.unit):
    def __init__(self, unit_in_si):
        self.unit_in_si = unit_in_si
    def __str__(self):
        return 'nbody '+self.unit_in_si.quantity
    @property
    def base(self):
        return ((1,self),)
    @property
    def factor(self):
        return 1.0

length = nbody_unit(units.m)
time = nbody_unit(units.s)
mass = nbody_unit(units.kg)
 
speed = length / time

class nbody_to_si(object): 
    
    def __init__(self, value1 , value2):
        self.value1 = value1
        self.value2 = value2
        if self.unit1.base == self.unit2.base:
            raise Exception("Must provide two orthogonal units for example mass and length or time and length")
        unit_was_found = [False, False, False]
        
        #if len(self.unit1.base) > 1:
        #    raise Exception("Currently cannot handle unit with more than one base, only meters or seconds or kg")
        #if len(self.unit2.base) > 1:
        #    raise Exception("Currently cannot handle unit with more than one base, only meters or seconds or kg")
        self.Gis1 = units.one / units.G
        
        base = self.Gis1.unit.base
        for i, x in enumerate(base):
            for y in self.unit1.base:
                if y[1] == x[1]:
                    unit_was_found[i] = True
            for y in self.unit2.base:
                if y[1] == x[1]:
                    unit_was_found[i] = True
        if len(filter(None, unit_was_found)) < 2:
            raise Exception("Must provide more units")
            
        
    @property
    def unit1(self):
        return self.value1.unit 
        
    @property
    def unit2(self):
        return self.value2.unit 
    
    def conversion_factors(self, unit_to_index):
        exponents_of_the_bases =  numpy.zeros((3,3))
        factors_of_the_bases =  numpy.zeros(3)
        for row, value in enumerate((self.Gis1, self.value1, self.value2)):
            for n, unit in value.unit.base:
                exponents_of_the_bases[row, unit_to_index[unit]] = n
            factors_of_the_bases[row] = value.number * value.unit.factor  
            
        log_factors_of_the_bases = numpy.log(factors_of_the_bases)
        return numpy.exp(numpy.linalg.solve(exponents_of_the_bases, log_factors_of_the_bases))
        
    @property    
    def units(self):
        unit_to_index = {}
        for i, x in enumerate(self.Gis1.unit.base):
            n , unit = x
            unit_to_index[unit] = i
            
        conversion_factors = self.conversion_factors(unit_to_index)
        
        result = []
        nbody_units = mass, length, time
        for n , unit  in self.Gis1.unit.base:
            index = unit_to_index[unit]
            conversion_factor_for_this_base_unit = conversion_factors[index]
            for nbody_unit in nbody_units:
                if nbody_unit.unit_in_si == unit:
                    result.append((nbody_unit, conversion_factor_for_this_base_unit * unit))
                    
        return result
        
    def to_si(self, value):
        factor = value.unit.factor
        number = value.number
        new_unit = 1
        for n, unit in value.unit.base:
            unit_in_nbody, unit_in_si = self.find_si_unit_for(unit)
            if not unit_in_si is None:
                factor = factor * (unit_in_si.factor ** n)
                new_unit *= (unit_in_si.base[0][1] ** n)
            else:
                new_unit *= (unit ** n)
        return new_unit(number * factor)
        
        
    def find_si_unit_for(self, unit):
        for unit_nbody, unit_in_si in self.units:
            if unit_nbody == unit:
                return unit_nbody, unit_in_si
        return None, None
        
    def find_nbody_unit_for(self, unit):
        for unit_nbody, unit_in_si in self.units:
            base_in_si = unit_in_si.base[0][1]
            if base_in_si == unit:
                return unit_nbody, unit_in_si
        return None, None
                
    def to_nbody(self, value):
        nbody_units_in_si = self.units
        base = value.unit.base
        factor = value.unit.factor
        number = value.number
        new_unit = 1
        for n, unit in base:
            unit_in_nbody, unit_in_si = self.find_nbody_unit_for(unit)
            if not unit_in_si is None:
                factor = factor / (unit_in_si.factor ** n)
                new_unit *= (unit_in_nbody.base[0][1] ** n)
            else:
                new_unit *= (unit ** n)
        return new_unit(number * factor)
        
                
                    
        

       
