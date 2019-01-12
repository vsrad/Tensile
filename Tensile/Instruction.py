"""
Modules contain lists of text instructions, Inst objects, or additional modules
They can be easily converted to string that represents all items in the list
and can be mixed with standard text.
The intent is to allow the kernel writer to express the structure of the
code (ie which instructions are a related module) so the scheduler can later
make intelligent and legal transformations.
"""
class Module:
  def __init__(self, name=""):
    self.name = name
    self.itemList = []

  def __str__(self):
    return "".join([str(x) for x in self.itemList])

  def toStr(self):
    return str(self)

  def append(self, inst):
    self.itemList.append(inst)

  def comment(self, comment):
    self.itemList.append("// %s\n"%comment)

  def instStr(self, *args):
    params = args[0:len(args)-1]
    comment = args[len(args)-1]
    formatting = "%s"
    if len(params) > 1:
      formatting += " %s"
    for i in range(0, len(params)-2):
      formatting += ", %s"
    instStr = formatting % (params)
    self.append("%-50s // %s\n" % (instStr, comment))

  def prettyPrint(self,indent=""):
    print "%s%s:"% (indent,self.name)
    for i in self.itemList:
      if isinstance(i, Module):
        i.prettyPrint(indent+"  ")
      elif isinstance(i, str):
        print indent, 'str:', str(i),
      else: # Inst
        print indent,"[",str(i),"]"

  """
  Count number of items with specified type in this Module
  Will recursively count occurrences in submodules
  """
  def countType(self,ttype):
    count=0
    for i in self.itemList:
      if isinstance(i, ttype):
        count += 1
      if isinstance(i, Module):
        count += i.countType(ttype)
      else:
        count += int(isinstance(i, ttype))
    return count

  def count(self):
    count=0
    for i in self.itemList:
      if isinstance(i, Module):
        count += i.count()
      else:
        count += 1
    return count

  """
  Return list of items in the Module
  Items may be other Modules, strings, or Inst
  """
  def items(self):
    return self.itemList


class StructuredModule(Module):
  def __init__(self, name=None):
    Module.__init__(self,name)
    self.header = Module("header")
    self.middle = Module("middle")
    self.footer =  Module("footer")

    self.append(self.header)
    self.append(self.middle)
    self.append(self.footer)

"""
Inst is an instruction.
Currently just stores text but over time may grow
"""
class Inst:
  def __init__(self, *args):
    params = args[0:len(args)-1]
    comment = args[len(args)-1]
    formatting = "%s"
    if len(params) > 1:
      formatting += " %s"
    for i in range(0, len(params)-2):
      formatting += ", %s"
    instStr = formatting % (params)
    self.text = "%-50s // %s\n" % (instStr, comment)

  def __str__(self):
    return self.text

  def toStr(self):
    return str(self)

  def countType(self,ttype):
    return int(isinstance(self, ttype))

# uniq type that can be used in Module.countType
class LoadInst (Inst):
  def __init__(self,*args):
    Inst.__init__(self,*args)

# uniq type that can be used in Module.countType
class LocalWriteInst (Inst):
  def __init__(self,*args):
    Inst.__init__(self,*args)

# uniq type that can be used in Module.countType
class LocalReadInst (Inst):
  def __init__(self,*args):
    Inst.__init__(self,*args)
