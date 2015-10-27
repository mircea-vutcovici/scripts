#! /usr/lib/jvm/java-8-oracle/jre/bin/jjs
hostname=""
jmxuser=""
jmxpasswd=""
port=12345
serviceURL = "service:jmx:rmi:///jndi/rmi://" + hostname + ":" + port+ "/jmxrmi"
StringArray = Java.type("java.lang.String[]")
var credentials = new StringArray(2)
credentials[0]=jmxuser
credentials[1]=jmxpasswd
HashMap = Java.type("java.util.HashMap")
var environment = new HashMap()
environment.put("jmx.remote.credentials",credentials)
var url = new javax.management.remote.JMXServiceURL(serviceURL)
var connector = javax.management.remote.JMXConnectorFactory.connect(url,environment)
mbeanServerConnection = connector.getMBeanServerConnection()

mbeanName="java.lang:type=MemoryPool,name=CMS Perm Gen"
ObjectName = Java.type("javax.management.ObjectName")
var objectName = new ObjectName(mbeanName)
var matchingNames = mbeanServerConnection.queryNames(objectName, null)
//matchingNamesIterator=matchingNames.iterator()
//while(matchingNamesIterator.hasNext()){ print(matchingNamesIterator.next()) }
//matchingNames.iterator().next()
attribute="Usage"
attributeValue=mbeanServerConnection.getAttribute(objectName, attribute)
print(Object.prototype.toString.call(attributeValue))
used=attributeValue.get("used")
max=attributeValue.get("max")
usedPercent=Math.round(used/max*10000)/100
print("CMS Perm Gen = " + usedPercent + "%")

attribute="Type"
attributeValue=mbeanServerConnection.getAttribute(objectName, attribute)
print(Object.prototype.toString.call(attributeValue))


attribute="CollectionUsageThreshold"
attributeValue=mbeanServerConnection.getAttribute(objectName, attribute)
print(Object.prototype.toString.call(attributeValue))


print(Object.prototype.toString.call(attributeValue).slice(8, -1))
