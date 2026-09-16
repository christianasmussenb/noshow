Class IRIS105.Util.WebAppSetup Extends %RegisteredObject
{

/// Crea o actualiza las Web Applications:
/// - API REST en /csp/mltest (DispatchClass: IRIS105.REST.NoShowService)
/// - Página CSP en /csp/mltest2 (solo CSP/ZEN habilitado)
/// - Chat WSGI en /csp/mlchat (wsgi.py del bind mount iris105-chat/)
ClassMethod ConfigureAll() As %Status
{
    #include %occErrors
    New $Namespace
    Set oldNS = $Namespace
    Set $Namespace = "%SYS"
    Set sc = $$$OK
    Try {
        Set sc = ..Upsert("/csp/mltest", "MLTEST", 1, 1, "IRIS105.REST.NoShowService", "/csp/mltest/")
        Quit:$$$ISERR(sc)
        Set sc = ..Upsert("/csp/mltest2", "MLTEST", 1, 0, "", "/csp/mltest2/")
        Quit:$$$ISERR(sc)
        Set sc = ..UpsertWSGI("/csp/mlchat", "MLTEST", "/iris/iris105-chat/", "wsgi", "app")
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Set $Namespace = oldNS
    Quit sc
}

/// Crea o actualiza una Web Application usando Security.Applications.
/// Reescrito tras un despliegue real (T18/HTC21-PLAN-PRUEBAS.md) contra una
/// instancia nueva: la versión anterior pasaba las propiedades como
/// %DynamicObject en vez de un array por referencia (Create/Modify esperan
/// ByRef array; un objeto pasado sin ".props" nunca transfiere nada), y usaba
/// CSPEnabled/RESTEnabled/AuthenticationMethods, que no existen como
/// propiedades en 2026.1 -- el equivalente vigente es Type + AutheEnabled.
/// Nunca se notó porque /csp/mltest en iris105 ya existía de un setup viejo
/// con Type y DispatchClass ya correctos; Modify() sobre props vacías no
/// tocaba esos campos. Contra una instancia nueva, Create() no seteaba nada.
ClassMethod Upsert(pName As %String, pNamespace As %String, pCSPEnabled As %Boolean = 1, pRESTEnabled As %Boolean = 0, pDispatchClass As %String = "", pCookiePath As %String = "") As %Status
{
    #include %occErrors
    Set status = $$$OK
    Try {
        If ##class(Security.Applications).Exists(pName) {
            Set status = ##class(Security.Applications).Delete(pName)
            Quit:$$$ISERR(status)
        }
        Kill props
        Set props("NameSpace") = pNamespace
        Set props("Type") = 2
        // Siempre setear DispatchClass (incluso vacío) para evitar que quede un valor heredado.
        Set props("DispatchClass") = pDispatchClass
        Set props("Enabled") = 1
        Set props("AutheEnabled") = 64
        Set props("MatchRoles") = ":%All"
        If pCookiePath'="" Set props("CookiePath") = pCookiePath
        Set status = ##class(Security.Applications).Create(pName, .props)
    } Catch ex {
        Set status = ex.AsStatus()
    }
    Quit status
}

/// Crea o actualiza una Web Application WSGI [Experimental] usando Security.Applications.
/// Patrón verificado en el repo `manten` (docker/init/load-sprint9.sh):
/// Type=2 + DispatchClass=%SYS.Python.WSGI, MatchRoles=":%All" es obligatorio (sin él,
/// IRIS devuelve 403 tras autenticar), y WSGIAppLocation requiere slash final.
ClassMethod UpsertWSGI(pName As %String, pNamespace As %String, pLocation As %String, pAppName As %String, pCallable As %String) As %Status
{
    #include %occErrors
    Set status = $$$OK
    Try {
        If ##class(Security.Applications).Exists(pName) {
            Set status = ##class(Security.Applications).Delete(pName)
            Quit:$$$ISERR(status)
        }
        Kill props
        Set props("NameSpace") = pNamespace
        Set props("Type") = 2
        Set props("DispatchClass") = "%SYS.Python.WSGI"
        Set props("Enabled") = 1
        Set props("AutheEnabled") = 64
        Set props("MatchRoles") = ":%All"
        Set props("WSGIAppName") = pAppName
        Set props("WSGICallable") = pCallable
        Set props("WSGIAppLocation") = pLocation
        Set props("WSGIDebug") = 0
        Set status = ##class(Security.Applications).Create(pName, .props)
    } Catch ex {
        Set status = ex.AsStatus()
    }
    Quit status
}

}
