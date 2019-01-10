class Module:
  def __init__(self, name=""):
    self.name = name
    self.instList = []
    self.itemList = []

  def __str__(self):
    return "\n".join([str(x) for x in self.instList])

  def toStr(self):
    return str(self)

  def append(self, inst):
    self.instList.append(inst)
    self.itemList.append(inst)

  def comment(self, comment):
    self.itemList.append(comment)

  def instStr(self, *args):
    params = args[0:len(args)-1]
    comment = args[len(args)-1]
    formatting = "%s"
    if len(params) > 1:
      formatting += " %s"
    for i in range(0, len(params)-2):
      formatting += ", %s"
    instStr = formatting % (params)
    self.append("%-50s // %s" % (instStr, comment))

  def prettyPrint(self,indent=""):
    print "%s%s:"% (indent,self.name)
    for i in self.itemList:
      if isinstance(i, Module):
        i.prettyPrint(indent+"  ")
      elif isinstance(i, str):
        print indent, '"', str(i) ,'"'
      else: # Inst
        print indent,"[",str(i),"]"

  def countType(self,ttype):
    count=0
    for i in self.itemList:
      if isinstance(i, Module):
        count += i.countType(ttype)
      else:
        count += int(isinstance(i, ttype))
    return count

class StructuredModule(Module):
  def __init__(self, name=None):
    Module.__init__(self,name)
    self.header = Module("header")
    self.middle = Module("middle")
    self.footer =  Module("footer")

    self.append(self.header)
    self.append(self.middle)
    self.append(self.footer)

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
    self.text = "%-50s // %s" % (instStr, comment)

  def __str__(self):
    return self.text + '\n'

  def toStr(self):
    return str(self)


class LoadInst (Inst):
  def __init__(self,*args):
    Inst.__init__(self,*args)
